#!/bin/bash
set -e

source /venv/main/bin/activate

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== Background Replacement & Lighting provisioning start ==="

APT_PACKAGES=()
PIP_PACKAGES=()

NODES=(
    "https://github.com/1038lab/ComfyUI-QwenVL.git"
    "https://github.com/1038lab/comfyui-rmbg.git"
    "https://github.com/chflame163/ComfyUI_LayerStyle.git"
    "https://github.com/cubiq/ComfyUI_essentials.git"
    "https://github.com/kijai/ComfyUI-DepthAnythingV2.git"
    "https://github.com/kijai/ComfyUI-KJNodes.git"
    "https://github.com/MaraScott/ComfyUI_MaraScott_Nodes.git"
    "https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git"
    "https://github.com/princepainter/Comfyui-PainterFluxImageEdit.git"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
    "https://github.com/rgthree/rgthree-comfy.git"
    "https://github.com/storyicon/comfyui_segment_anything.git"
    "https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git"
    "https://github.com/TTPlanetPig/Comfyui_TTP_Toolset.git"
    "https://github.com/TinyTerra/ComfyUI_tinyterraNodes.git"
    "https://github.com/yolain/ComfyUI-Easy-Use.git"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
    "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
)

TEXT_ENCODERS=(
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors"
    "https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors"
)

GGUF_TEXT_ENCODERS=(
    "https://huggingface.co/BennyDaBall/Qwen3-4b-Z-Image-Engineer-V4/resolve/main/Qwen3-4b-Z-Image-Engineer-V4-Q8_0.gguf"
)

DIFFUSION_MODELS=(
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
    "https://huggingface.co/kp-forks/FLUX.2-klein-9B/resolve/main/flux-2-klein-9b.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors"
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"
)

MODEL_PATCHES=(
    "https://huggingface.co/alibaba-pai/Z-Image-Turbo-Fun-Controlnet-Union-2.0/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union-2.0.safetensors"
)

LORAS=(
    "https://huggingface.co/alibaba-pai/Z-Image-Fun-Lora-Distill/resolve/main/Z-Image-Fun-Lora-Distill-8-Steps-2602-ComfyUI.safetensors"
    "https://huggingface.co/F16/z-image-turbo-flow-dpo/resolve/main/zit_fdpo_v1.safetensors"
)

DEPTHANYTHING_MODELS=(
    "https://huggingface.co/depth-anything/Depth-Anything-V2-Large/resolve/main/depth_anything_v2_vitl.pth"
    "https://huggingface.co/Kijai/DepthAnythingV2-safetensors/resolve/main/depth_anything_v2_vits_fp16.safetensors"
)

SAMS=(
    "https://huggingface.co/alexgenovese/sams/resolve/main/sam_vit_h_4b8939.pth"
)

SEEDVR2_MODELS=(
    "https://huggingface.co/cmeka/SeedVR2-GGUF/resolve/main/seedvr2_ema_3b-Q8_0.gguf"
    "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors"
)

UPSCALE_MODELS=(
    "https://huggingface.co/gemasai/4x_NMKD-Siax_200k/resolve/main/4x_NMKD-Siax_200k.pth?download=true"
)

WORKFLOWS=(
    "https://civitai.com/api/download/models/2790553"
)

# The workflow JSON references two additional custom files that were not exposed
# with direct URLs in the workflow metadata:
# - beyondREALITY_beyondREALITYZIMAGE.safetensors
# - Klein 一致性增强.safetensors
# Add them manually to ComfyUI/models/diffusion_models and ComfyUI/models/loras
# if your chosen branch of the workflow uses those nodes.

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
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders" "${GGUF_TEXT_ENCODERS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/model_patches" "${MODEL_PATCHES[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras" "${LORAS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/depthanything" "${DEPTHANYTHING_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/sams" "${SAMS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/seedvr2" "${SEEDVR2_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/upscale_models" "${UPSCALE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/user/default/workflows" "${WORKFLOWS[@]}"

    # Match the exact filenames used in the workflow graph.
    provisioning_copy_alias "${COMFYUI_DIR}/models/vae/ae.safetensors" "${COMFYUI_DIR}/models/vae/z_image_turbo-vae.safetensors"
    provisioning_copy_alias "${COMFYUI_DIR}/models/diffusion_models/flux-2-klein-9b.safetensors" "${COMFYUI_DIR}/models/diffusion_models/new_flux-2-klein-9b.safetensors"
    provisioning_copy_alias "${COMFYUI_DIR}/models/seedvr2/ema_vae_fp16.safetensors" "${COMFYUI_DIR}/models/vae/ema_vae_fp16.safetensors"
}

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

cd "${COMFYUI_DIR}"
python main.py --listen 0.0.0.0 --port 8188
