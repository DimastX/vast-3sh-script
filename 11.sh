#!/bin/bash
# Без set -e: ошибки скачивания/проверки не останавливают запуск ComfyUI.

set -u

if [[ -f /venv/main/bin/activate ]]; then
    source /venv/main/bin/activate
fi

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== Wan Animate God Mode V3 provisioning start ==="

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

# Опционально: прямые ссылки на кастомные LoRA из workflow
SADIE01_URL="${SADIE01_URL:-}"
SYDNEY01_URL="${SYDNEY01_URL:-}"

MODEL_SPECS=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors|models/clip_vision|clip_vision_h.safetensors"
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors|models/text_encoders|umt5_xxl_fp8_e4m3fn_scaled.safetensors"
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors|models/vae|wan_2.1_vae.safetensors"
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_animate_14B_bf16.safetensors|models/diffusion_models|wan2.2_animate_14B_bf16.safetensors"
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_low_noise_14B_fp16.safetensors|models/diffusion_models|wan2.2_t2v_low_noise_14B_fp16.safetensors"
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_animate_14B_relight_lora_bf16.safetensors|models/loras|wan2.2_animate_14B_relight_lora_bf16.safetensors"
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors|models/loras|i2v_lightx2v_low_noise_model.safetensors"
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_t2v_lightx2v_4steps_lora_v1.1_low_noise.safetensors|models/loras|t2v_lightx2v_low_noise_model.safetensors"
    "https://huggingface.co/primalfearfear/BrHelperHIGH/resolve/main/BreastsLoRA_ByHearmemanAI_HighNoise-000070.safetensors|models/loras|BreastsLoRA_ByHearmemanAI_HighNoise-000070.safetensors"
    "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx|models/detection|yolov10m.onnx"
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx|models/detection|vitpose_h_wholebody_model.onnx"
    "https://huggingface.co/2ch/OnnxModels/resolve/main/yolox_l.onnx|models/detection|yolox_l.onnx"
    "https://huggingface.co/yzd-v/DWPose/resolve/main/dw-ll_ucoco_384_bs5.torchscript.pt|models/detection|dw-ll_ucoco_384_bs5.torchscript.pt"
    "https://huggingface.co/Kijai/sam2-safetensors/resolve/main/sam2.1_hiera_base_plus.safetensors|models/sam2|sam2.1_hiera_base_plus.safetensors"
    "https://huggingface.co/risunobushi/1xSkinContrast/resolve/main/1xSkinContrast-SuperUltraCompact.pth?download=true|models/upscale_models|1xSkinContrast-SuperUltraCompact.pth"
    "https://huggingface.co/Acly/rife/resolve/main/rife49.pth?download=true|models/rife|rife49.pth"
)
[[ -n "${SADIE01_URL}" ]] && MODEL_SPECS+=( "${SADIE01_URL}|models/loras|Sadie01_LowNoise.safetensors" )
[[ -n "${SYDNEY01_URL}" ]] && MODEL_SPECS+=( "${SYDNEY01_URL}|models/loras|Sydney01_LowNoise.safetensors" )

auth_args_for_url() {
    local url="$1"
    local args=()
    if [[ -n "${HF_TOKEN:-}" && "$url" =~ huggingface\.co ]]; then
        args=(--header="Authorization: Bearer ${HF_TOKEN}")
    elif [[ -n "${CIVITAI_TOKEN:-}" && "$url" =~ civitai\.com ]]; then
        args=(--header="Authorization: Bearer ${CIVITAI_TOKEN}")
    fi
    printf '%s\n' "${args[@]}"
}

clone_comfyui() {
    if [[ ! -d "${COMFYUI_DIR}" ]]; then
        git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}" || echo " [!] git clone ComfyUI failed"
    fi
}

install_base_reqs() {
    cd "${COMFYUI_DIR}" || return 0
    if [[ -f requirements.txt ]]; then
        pip install --no-cache-dir -r requirements.txt || echo " [!] pip base requirements failed"
    fi
}

install_nodes() {
    mkdir -p "${COMFYUI_DIR}/custom_nodes"
    cd "${COMFYUI_DIR}/custom_nodes" || return 0
    for repo in "${NODES[@]}"; do
        local dir="${repo##*/}"
        dir="${dir%.git}"
        if [[ -d "${dir}" ]]; then
            (cd "${dir}" && git pull --ff-only 2>/dev/null || git fetch --all 2>/dev/null || true)
        else
            git clone "${repo}" "${dir}" --recursive || echo " [!] Clone failed: ${repo}"
        fi
        if [[ -f "${dir}/requirements.txt" ]]; then
            pip install --no-cache-dir -r "${dir}/requirements.txt" || echo " [!] pip failed: ${dir}"
        fi
    done
}

# Проверка доступности URL (wget --spider). Только отчёт, без exit.
check_model_urls() {
    echo ""
    echo "=== Проверка ссылок на модели (wget --spider) ==="
    for spec in "${MODEL_SPECS[@]}"; do
        IFS='|' read -r url rel_dir filename <<< "${spec}"
        if [[ -z "${url}" ]]; then
            echo " [skip] пустой URL для ${rel_dir}/${filename}"
            continue
        fi
        mapfile -t auth_args < <(auth_args_for_url "$url")
        if wget "${auth_args[@]}" --spider --tries=2 --timeout=30 "$url" >/dev/null 2>&1; then
            echo " [OK]   ${filename}"
            echo "        ${url}"
        else
            echo " [WARN] недоступен или 403/404 (проверьте токен/URL): ${filename}"
            echo "        ${url}"
        fi
    done
    if [[ -z "${SADIE01_URL}" ]]; then
        echo " [info] SADIE01_URL не задан — Sadie01_LowNoise.safetensors не в списке загрузок"
    fi
    if [[ -z "${SYDNEY01_URL}" ]]; then
        echo " [info] SYDNEY01_URL не задан — Sydney01_LowNoise.safetensors не в списке загрузок"
    fi
    echo "=== конец проверки ссылок ==="
    echo ""
}

download_model() {
    local url="$1"
    local rel_dir="$2"
    local filename="$3"
    local target_dir="${COMFYUI_DIR}/${rel_dir}"
    local target_file="${target_dir}/${filename}"

    mkdir -p "${target_dir}"
    if [[ -f "${target_file}" ]]; then
        echo "Already exists: ${target_file}"
        return 0
    fi

    if [[ -z "${url}" ]]; then
        echo " [skip] нет URL для ${filename}"
        return 0
    fi

    mapfile -t auth_args < <(auth_args_for_url "$url")
    wget "${auth_args[@]}" \
        --show-progress \
        --tries=5 \
        --waitretry=5 \
        --retry-connrefused \
        --timeout=30 \
        --read-timeout=30 \
        -c \
        -e dotbytes=4M \
        -O "${target_file}" \
        "$url" || { rm -f "${target_file}" 2>/dev/null; echo " [!] Download failed: ${url}"; return 0; }
}

report_missing_files() {
    local missing=0
    echo ""
    echo "=== Итог: файлы под workflow ==="
    for spec in "${MODEL_SPECS[@]}"; do
        IFS='|' read -r _url rel_dir filename <<< "${spec}"
        local f="${COMFYUI_DIR}/${rel_dir}/${filename}"
        if [[ -f "${f}" ]]; then
            echo " [есть] ${f}"
        else
            echo " [нет]  ${f}"
            missing=1
        fi
    done
    if [[ "${missing}" -ne 0 ]]; then
        echo "Часть файлов отсутствует — докачайте вручную или задайте SADIE01_URL / SYDNEY01_URL."
    fi
    echo ""
}

provision_start() {
    clone_comfyui
    install_base_reqs
    install_nodes

    check_model_urls

    for spec in "${MODEL_SPECS[@]}"; do
        IFS='|' read -r url rel_dir filename <<< "${spec}"
        download_model "$url" "$rel_dir" "$filename"
    done

    report_missing_files
}

provision_start

if cd "${COMFYUI_DIR}"; then
    python main.py --listen 0.0.0.0 --port 8188
else
    echo " [!] Не удалось перейти в ${COMFYUI_DIR} — ComfyUI не запущен"
fi
