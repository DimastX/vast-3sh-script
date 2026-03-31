#!/bin/bash
set -e

source /venv/main/bin/activate

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== FaceSwap Flux2 provisioning start ==="

APT_PACKAGES=()
PIP_PACKAGES=()

NODES=(
    "https://github.com/rgthree/rgthree-comfy.git"
    "https://github.com/yolain/ComfyUI-Easy-Use.git"
)

TEXT_ENCODERS=(
    "https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors"
)

DIFFUSION_MODELS=(
    "https://huggingface.co/black-forest-labs/FLUX.2-klein-9B/resolve/main/flux-2-klein-9b.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"
)

# Optional:
# - Set WORKFLOW_URL to auto-download faceswap workflow into user/default/workflows.

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

    if [[ -n "${WORKFLOW_URL:-}" ]]; then
        provisioning_get_files "${COMFYUI_DIR}/user/default/workflows" "${WORKFLOW_URL}"
    fi

    # Match exact names selected in faceswap.json widgets.
    provisioning_copy_alias "${COMFYUI_DIR}/models/text_encoders/qwen_3_8b_fp8mixed.safetensors" "${COMFYUI_DIR}/models/text_encoders/qwen_3_8b.safetensors"
}

provisioning_start

cd "${COMFYUI_DIR}"
python main.py --listen 0.0.0.0 --port 8188
