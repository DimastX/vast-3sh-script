#!/bin/bash
set -e

source /venv/main/bin/activate

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== Moody Z-Image i2i provisioning start ==="

APT_PACKAGES=()
PIP_PACKAGES=()

NODES=(
    "https://github.com/kijai/ComfyUI-Florence2.git"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
    "https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git"
    "https://github.com/rgthree/rgthree-comfy.git"
    "https://github.com/cubiq/ComfyUI_essentials.git"
    "https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git"
    "https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git"
    "https://github.com/kijai/ComfyUI-KJNodes.git"
)

TEXT_ENCODERS=(
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors"
)

DIFFUSION_MODELS=(
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors"
)

UPSCALE_MODELS=(
    "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth?download=true|4x-UltraSharp.pth"
    "https://huggingface.co/notkenski/upscalers/resolve/main/1xSkinContrast-High-SuperUltraCompact.pth?download=true|1xSkinContrast-High-SuperUltraCompact.pth"
)

SAMS=(
    "https://huggingface.co/licyk/comfyui-extension-models/resolve/main/ComfyUI-Impact-Pack/sam_vit_b_01ec64.pth"
)

ULTRALYTICS_BBOX=(
    "https://huggingface.co/alexgenovese/ultralytics/resolve/main/bbox/face_yolov8m.pt?download=true"
)

SEEDVR2_MODELS=(
    "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_sharp_fp16.safetensors"
    "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors"
)

# Optional:
# - Set MOODY_MODEL_URL to download your preferred Moody checkpoint as
#   models/diffusion_models/moody-v10.safetensors.
# - Set WORKFLOW_URL to auto-download the workflow JSON into user/default/workflows.
# - The Florence2 node downloads MiaoshouAI/Florence-2-base-PromptGen-v2.0 on first use.
OPTIONAL_LORAS=(
    "https://huggingface.co/tarn59/pixel_art_style_lora_z_image_turbo/resolve/main/pixel_art_style_z_image_turbo.safetensors?download=true|pixel_art_style_z_image_turbo.safetensors"
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

provisioning_copy_alias() {
    local source_path="$1"
    local target_path="$2"

    if [[ -f "$source_path" && ! -f "$target_path" ]]; then
        echo "Creating alias: $target_path"
        cp "$source_path" "$target_path"
    fi
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
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/upscale_models" "${UPSCALE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/sams" "${SAMS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox" "${ULTRALYTICS_BBOX[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/seedvr2" "${SEEDVR2_MODELS[@]}"

    if [[ -n "${MOODY_MODEL_URL:-}" ]]; then
        provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models" "${MOODY_MODEL_URL}|moody-v10.safetensors"
    else
        # Fallback so the workflow opens immediately even before the real Moody model is added.
        provisioning_copy_alias "${COMFYUI_DIR}/models/diffusion_models/z_image_turbo_bf16.safetensors" "${COMFYUI_DIR}/models/diffusion_models/moody-v10.safetensors"
    fi

    if [[ -n "${OPTIONAL_PIXEL_ART_LORA:-}" ]]; then
        provisioning_get_files "${COMFYUI_DIR}/models/loras" "${OPTIONAL_LORAS[@]}"
    fi

    if [[ -n "${WORKFLOW_URL:-}" ]]; then
        provisioning_get_files "${COMFYUI_DIR}/user/default/workflows" "${WORKFLOW_URL}"
    fi

    provisioning_copy_alias "${COMFYUI_DIR}/models/seedvr2/ema_vae_fp16.safetensors" "${COMFYUI_DIR}/models/vae/ema_vae_fp16.safetensors"
}

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

cd "${COMFYUI_DIR}"
python main.py --listen 0.0.0.0 --port 8188
