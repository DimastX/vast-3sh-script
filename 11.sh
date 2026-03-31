#!/bin/bash
set -e

source /venv/main/bin/activate

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== Wan Animate God Mode V3 provisioning start ==="

APT_PACKAGES=()
PIP_PACKAGES=()

NODES=(
    "https://github.com/kijai/ComfyUI-WanVideoWrapper.git"
    "https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git"
    "https://github.com/kijai/ComfyUI-KJNodes.git"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    "https://github.com/kijai/ComfyUI-segment-anything-2.git"
    "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
    "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git"
    "https://github.com/rgthree/rgthree-comfy.git"
)

CLIP_VISION=(
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"
)

TEXT_ENCODERS=(
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
)

DIFFUSION_MODELS=(
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_animate_14B_bf16.safetensors"
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_low_noise_14B_fp16.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"
)

DETECTION_MODELS=(
    "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx"
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx"
    "https://huggingface.co/2ch/OnnxModels/resolve/main/yolox_l.onnx"
    "https://huggingface.co/yzd-v/DWPose/resolve/main/dw-ll_ucoco_384_bs5.torchscript.pt"
)

SAMS=(
    "https://huggingface.co/Kijai/sam2-safetensors/resolve/main/sam2.1_hiera_base_plus.safetensors"
)

UPSCALE_MODELS=(
    "https://huggingface.co/risunobushi/1xSkinContrast/resolve/main/1xSkinContrast-SuperUltraCompact.pth?download=true|1xSkinContrast-SuperUltraCompact.pth"
)

RIFE_MODELS=(
    "https://huggingface.co/Acly/rife/resolve/main/rife49.pth?download=true|rife49.pth"
)

LORAS=(
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_animate_14B_relight_lora_bf16.safetensors"
)

# Custom workflow-specific LoRAs without stable public URLs in JSON:
#   - i2v_lightx2v_low_noise_model.safetensors
#   - t2v_lightx2v_low_noise_model.safetensors
#   - Sadie01_LowNoise.safetensors
#   - Sydney01_LowNoise.safetensors
#   - BreastsLoRA_ByHearmemanAI_HighNoise-000070.safetensors
#
# You can provide any direct URLs via:
#   CUSTOM_LORA_URLS="url1|filename1,url2|filename2,..."
#
# Example:
#   export CUSTOM_LORA_URLS="https://.../Sadie01_LowNoise.safetensors|Sadie01_LowNoise.safetensors"

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
            wget "${auth_args[@]}" --show-progress -e dotbytes=4M -O "$output_path" "$url"
        else
            wget "${auth_args[@]}" -nc --content-disposition --show-progress -e dotbytes=4M -P "$dir" "$url"
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

provisioning_get_custom_lora_urls() {
    if [[ -z "${CUSTOM_LORA_URLS:-}" ]]; then
        return
    fi

    IFS=',' read -r -a custom_specs <<< "${CUSTOM_LORA_URLS}"
    if [[ ${#custom_specs[@]} -gt 0 ]]; then
        provisioning_get_files "${COMFYUI_DIR}/models/loras" "${custom_specs[@]}"
    fi
}

provisioning_validate_required_files() {
    local missing=0
    local required=(
        "${COMFYUI_DIR}/models/clip_vision/clip_vision_h.safetensors"
        "${COMFYUI_DIR}/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
        "${COMFYUI_DIR}/models/vae/wan_2.1_vae.safetensors"
        "${COMFYUI_DIR}/models/diffusion_models/wan2.2_animate_14B_bf16.safetensors"
        "${COMFYUI_DIR}/models/diffusion_models/wan2.2_t2v_low_noise_14B_fp16.safetensors"
        "${COMFYUI_DIR}/models/loras/wan2.2_animate_14B_relight_lora_bf16.safetensors"
        "${COMFYUI_DIR}/models/loras/i2v_lightx2v_low_noise_model.safetensors"
        "${COMFYUI_DIR}/models/loras/t2v_lightx2v_low_noise_model.safetensors"
        "${COMFYUI_DIR}/models/loras/Sadie01_LowNoise.safetensors"
        "${COMFYUI_DIR}/models/loras/Sydney01_LowNoise.safetensors"
        "${COMFYUI_DIR}/models/loras/BreastsLoRA_ByHearmemanAI_HighNoise-000070.safetensors"
        "${COMFYUI_DIR}/models/detection/yolov10m.onnx"
        "${COMFYUI_DIR}/models/detection/vitpose_h_wholebody_model.onnx"
        "${COMFYUI_DIR}/models/detection/yolox_l.onnx"
        "${COMFYUI_DIR}/models/detection/dw-ll_ucoco_384_bs5.torchscript.pt"
        "${COMFYUI_DIR}/models/sam2/sam2.1_hiera_base_plus.safetensors"
        "${COMFYUI_DIR}/models/upscale_models/1xSkinContrast-SuperUltraCompact.pth"
        "${COMFYUI_DIR}/models/rife/rife49.pth"
    )

    echo "Validating required workflow files..."
    for file in "${required[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo " [!] Missing: $file"
            missing=1
        fi
    done

    if [[ "$missing" -ne 0 ]]; then
        echo ""
        echo "Some required files are missing. Add direct URLs via CUSTOM_LORA_URLS for custom LoRAs and rerun."
        exit 1
    fi
}

provisioning_start() {
    provisioning_get_apt_packages
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    provisioning_get_nodes
    provisioning_get_pip_packages

    provisioning_get_files "${COMFYUI_DIR}/models/clip_vision" "${CLIP_VISION[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders" "${TEXT_ENCODERS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/detection" "${DETECTION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras" "${LORAS[@]}"
    provisioning_get_custom_lora_urls
    provisioning_get_files "${COMFYUI_DIR}/models/sam2" "${SAMS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/upscale_models" "${UPSCALE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/rife" "${RIFE_MODELS[@]}"

    provisioning_validate_required_files
}

provisioning_start

cd "${COMFYUI_DIR}"
python main.py --listen 0.0.0.0 --port 8188
