#!/bin/bash
set -e

source /venv/main/bin/activate

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== Ultimate cloth changer provisioning start ==="

APT_PACKAGES=()
PIP_PACKAGES=()

NODES=(
    "https://github.com/ai-shizuka/ComfyUI-tbox.git"
    "https://github.com/yolain/ComfyUI-Easy-Use.git"
    "https://github.com/Suzie1/was-node-suite-comfyui.git"
    "https://github.com/chflame163/ComfyUI_LayerStyle_Advance.git"
    "https://github.com/un-seen/comfyui-tensorops.git"
    "https://github.com/cubiq/ComfyUI_essentials.git"
    "https://github.com/Acly/comfyui-inpaint-nodes.git"
    "https://github.com/city96/ComfyUI-GGUF.git"
    "https://github.com/lrzjason/Comfyui-In-Context-Lora-Utils.git"
    "https://github.com/kaibioinfo/ComfyUI_AdvancedRefluxControl.git"
    "https://github.com/chrisgoringe/cg-use-everywhere.git"
)

TEXT_ENCODERS=(
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors"
)

CLIP_VISION=(
    "https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors"
)

UNET_MODELS=(
    "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors"
    "https://huggingface.co/black-forest-labs/FLUX.1-Fill-dev/resolve/main/flux1-fill-dev.safetensors"
)

STYLE_MODELS=(
    "https://huggingface.co/black-forest-labs/FLUX.1-Redux-dev/resolve/main/flux1-redux-dev.safetensors|redux.safetensors"
)

LORA_MODELS=(
    "https://civitai.com/api/download/models/1041442|Flux.1_Turbo_Detailer.safetensors"
    "https://civitai.com/api/download/models/964759|FLUX.1-Turbo-Alpha.safetensors"
)

SAMS=(
    "https://huggingface.co/Kijai/sam2-safetensors/resolve/main/sam2_hiera_base_plus.safetensors"
)

FLORENCE2_BASE_FT_FILES=(
    "https://huggingface.co/chflame163/ComfyUI_LayerStyle/resolve/main/ComfyUI/models/florence2/base-ft/config.json"
    "https://huggingface.co/chflame163/ComfyUI_LayerStyle/resolve/main/ComfyUI/models/florence2/base-ft/configuration_florence2.py"
    "https://huggingface.co/chflame163/ComfyUI_LayerStyle/resolve/main/ComfyUI/models/florence2/base-ft/modeling_florence2.py"
    "https://huggingface.co/chflame163/ComfyUI_LayerStyle/resolve/main/ComfyUI/models/florence2/base-ft/preprocessor_config.json"
    "https://huggingface.co/chflame163/ComfyUI_LayerStyle/resolve/main/ComfyUI/models/florence2/base-ft/processing_florence2.py"
    "https://huggingface.co/chflame163/ComfyUI_LayerStyle/resolve/main/ComfyUI/models/florence2/base-ft/pytorch_model.bin"
    "https://huggingface.co/chflame163/ComfyUI_LayerStyle/resolve/main/ComfyUI/models/florence2/base-ft/tokenizer.json"
    "https://huggingface.co/chflame163/ComfyUI_LayerStyle/resolve/main/ComfyUI/models/florence2/base-ft/tokenizer_config.json"
    "https://huggingface.co/chflame163/ComfyUI_LayerStyle/resolve/main/ComfyUI/models/florence2/base-ft/vocab.json"
)

WORKFLOWS=(
    "https://civitai.com/api/download/models/1740871"
)

provisioning_clone_comfyui() {
    if [[ ! -d "${COMFYUI_DIR}" ]]; then
        echo "Cloning ComfyUI..."
        git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}"
    fi
    cd "${COMFYUI_DIR}"
}

provisioning_install_base_reqs() {
    if [[ -f requirements.txt ]]; then
        echo "Installing base requirements..."
        pip install --no-cache-dir -r requirements.txt
    fi
}

provisioning_get_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
        echo "Installing apt packages..."
        sudo apt update && sudo apt install -y "${APT_PACKAGES[@]}"
    fi
}

provisioning_get_pip_packages() {
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        echo "Installing extra pip packages..."
        pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    fi
}

provisioning_get_files() {
    if [[ $# -lt 2 ]]; then return; fi
    local dir="$1"
    shift
    local files=("$@")

    mkdir -p "$dir"

    for spec in "${files[@]}"; do
        local url="$spec"
        local output_name=""
        local auth_args=()

        if [[ "$spec" == *"|"* ]]; then
            url="${spec%%|*}"
            output_name="${spec#*|}"
        fi

        if [[ -n "$HF_TOKEN" && "$url" =~ huggingface\.co ]]; then
            auth_args=(--header="Authorization: Bearer $HF_TOKEN")
        elif [[ -n "$CIVITAI_TOKEN" && "$url" =~ civitai\.com ]]; then
            auth_args=(--header="Authorization: Bearer $CIVITAI_TOKEN")
        fi

        echo "Downloading: $url"
        if [[ -n "$output_name" ]]; then
            local output_path="${dir}/${output_name}"
            if [[ -f "$output_path" ]]; then
                echo "Already exists: $output_path"
                continue
            fi

            wget "${auth_args[@]}" --show-progress -e dotbytes=4M -O "$output_path" "$url" || echo " [!] Download failed: $url"
        else
            wget "${auth_args[@]}" -nc --content-disposition --show-progress -e dotbytes=4M -P "$dir" "$url" || echo " [!] Download failed: $url"
        fi
    done
}

provisioning_get_nodes() {
    mkdir -p "${COMFYUI_DIR}/custom_nodes"
    cd "${COMFYUI_DIR}/custom_nodes"

    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        dir="${dir%.git}"
        path="./${dir}"

        if [[ -d "$path" ]]; then
            echo "Updating node: $dir"
            (
                cd "$path" && \
                git pull --ff-only 2>/dev/null || \
                git fetch --all 2>/dev/null || true
            )
        else
            echo "Cloning node: $dir"
            git clone "$repo" "$path" --recursive || echo " [!] Clone failed: $repo"
        fi

        if [[ -f "${path}/requirements.txt" ]]; then
            echo "Installing deps for $dir..."
            pip install --no-cache-dir -r "${path}/requirements.txt" || echo " [!] pip failed for $dir"
        fi
    done
}

provisioning_start() {
    provisioning_get_apt_packages
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    provisioning_get_nodes
    provisioning_get_pip_packages

    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders" "${TEXT_ENCODERS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip_vision" "${CLIP_VISION[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/unet" "${UNET_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/style_models" "${STYLE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras" "${LORA_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/sams" "${SAMS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/florence2/base-ft" "${FLORENCE2_BASE_FT_FILES[@]}"
    provisioning_get_files "${COMFYUI_DIR}/user/default/workflows" "${WORKFLOWS[@]}"
}

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

cd "${COMFYUI_DIR}"
python main.py --listen 0.0.0.0 --port 8188
