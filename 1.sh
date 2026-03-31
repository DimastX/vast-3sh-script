#!/bin/bash
set -e
source /venv/main/bin/activate

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== Custom ComfyUI provisioning start ==="

APT_PACKAGES=()
PIP_PACKAGES=()

NODES=(
    # База WAN workflow
    "https://github.com/kijai/ComfyUI-WanVideoWrapper.git"
    "https://github.com/chflame163/ComfyUI_LayerStyle.git"
    "https://github.com/yolain/ComfyUI-Easy-Use.git"
    "https://github.com/kijai/ComfyUI-KJNodes.git"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    "https://github.com/kijai/ComfyUI-segment-anything-2.git"
    "https://github.com/cubiq/ComfyUI_essentials.git"
    "https://github.com/fq393/ComfyUI-ZMG-Nodes.git"
    "https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git"
    "https://github.com/rgthree/rgthree-comfy.git"
    "https://github.com/jnxmx/ComfyUI_HuggingFace_Downloader.git"

    # Teskor utils
    "https://github.com/teskor-hub/NEW-UTILS.git"
    "https://github.com/teskor-hub/comfyui-teskors-utils.git"

    # Для missing nodes
    "https://github.com/TinyTerra/ComfyUI_tinyterraNodes.git"
    "https://github.com/shadowcz007/ComfyUI-ComfyMath.git"
    "https://github.com/PGCRT/CRT-Nodes.git"
)

CLIP_MODELS=(
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors"
)

CLIP_VISION=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors"
)

TEXT_ENCODERS=(
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/text_enc.safetensors"
)

DIFFUSION_MODELS=(
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanModel.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/vae.safetensors"
)

DETECTION_MODELS=(
    "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx"
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_data.bin"
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx"
)

LORAS=(
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanFun.reworked.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/light.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanPusa.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/wan.reworked.safetensors"
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

provisioning_get_files() {
    if [[ $# -lt 2 ]]; then return; fi
    local dir="$1"
    shift
    local files=("$@")

    mkdir -p "$dir"

    for url in "${files[@]}"; do
        local auth_header=""
        if [[ -n "$HF_TOKEN" && "$url" =~ huggingface\.co ]]; then
            auth_header="--header=Authorization: Bearer $HF_TOKEN"
        elif [[ -n "$CIVITAI_TOKEN" && "$url" =~ civitai\.com ]]; then
            auth_header="--header=Authorization: Bearer $CIVITAI_TOKEN"
        fi

        echo "Downloading: $url"
        wget $auth_header -nc --content-disposition --show-progress -e dotbytes=4M -P "$dir" "$url" || echo " [!] Download failed: $url"
    done
}

provisioning_start() {
    provisioning_get_apt_packages
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    provisioning_get_nodes
    provisioning_get_pip_packages

    provisioning_get_files "${COMFYUI_DIR}/models/clip" "${CLIP_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip_vision" "${CLIP_VISION[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders" "${TEXT_ENCODERS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/detection" "${DETECTION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras" "${LORAS[@]}"
}

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

cd "${COMFYUI_DIR}"
python main.py --listen 0.0.0.0 --port 8188