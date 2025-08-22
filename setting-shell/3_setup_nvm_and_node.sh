#!/bin/bash

# ====== 에러 처리 함수 ======
handle_error() {
    echo "❌ 오류가 발생했습니다: $1"
    exit 1
}

# ====== Node.js 환경 설정 여부 확인 ======
check_node_setup() {
    # nvm 설치 여부 확인
    if ! command -v nvm &> /dev/null; then
        return 1
    fi

    # Node.js 버전 확인
    NODE_VERSIONS=("14.8.0" "16.20.0" "18.19.0")
    for version in "${NODE_VERSIONS[@]}"; do
        if ! nvm ls "$version" | grep -q "$version"; then
            return 1
        fi
    done

    # nvm 설정 확인
    if [ -n "$ZSH_VERSION" ]; then
        SHELL_RC="$HOME/.zshrc"
    else
        SHELL_RC="$HOME/.bashrc"
    fi

    if ! grep -q 'NVM_DIR' "$SHELL_RC"; then
        return 1
    fi

    return 0
}

# Node.js 환경 설정 여부 확인
if check_node_setup; then
    echo "✅ NVM 및 Node.js 멀티버전 환경이 이미 구성되어 있습니다. 스크립트를 건너뜁니다."
    exit 0
fi

# ====== Node.js 14.8.0이면 스킵 ======
skip_node_setup=false
if command -v node &> /dev/null; then
    current_node_version=$(node -v | sed 's/v//')
    if [ "$current_node_version" = "14.8.0" ]; then
        echo "현재 Node.js 버전이 14.8.0입니다. nvm 및 node 멀티버전 설치/설정은 건너뜁니다."
        skip_node_setup=true
    fi
fi

if [ "$skip_node_setup" = false ]; then
    echo "=== nvm(Node Version Manager) 설치 및 Node.js 멀티버전 환경 구성 ==="

    # nvm 설치
    if ! command -v nvm &> /dev/null; then
        echo "nvm이 설치되어 있지 않습니다. 설치를 시작합니다..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

        # .zshrc 또는 .bashrc에 nvm 설정 추가
        if [ -n "$ZSH_VERSION" ]; then
            SHELL_RC="$HOME/.zshrc"
        else
            SHELL_RC="$HOME/.bashrc"
        fi

        if ! grep -q 'NVM_DIR' "$SHELL_RC"; then
            echo 'export NVM_DIR="$HOME/.nvm"' >> "$SHELL_RC"
            echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> "$SHELL_RC"
        fi

        echo "nvm 설치 및 환경설정이 완료되었습니다."
    else
        echo "✅ nvm이 이미 설치되어 있습니다."
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    fi

    # 원하는 Node.js 버전 설치
    NODE_VERSIONS=("14.8.0" "16.20.0" "18.19.0")
    for version in "${NODE_VERSIONS[@]}"; do
        if nvm ls "$version" | grep -q "$version"; then
            echo "✅ Node.js $version 이(가) 이미 설치되어 있습니다."
        else
            echo "Node.js $version 설치 중..."
            nvm install "$version"
        fi
    done

    # 사용할 Node.js 버전 선택
    echo ""
    echo "설치된 Node.js 버전:"
    nvm ls

    echo ""
    echo "기본으로 사용할 Node.js 버전을 입력하세요 (예: 14.8.0):"
    read -p "버전 입력: " default_version

    if nvm ls "$default_version" | grep -q "$default_version"; then
        nvm alias default "$default_version"
        nvm use "$default_version"
        echo "✅ Node.js $default_version 버전이 기본값으로 설정되었습니다."
    else
        echo "❌ 입력한 버전이 설치되어 있지 않습니다. nvm ls로 설치된 버전을 확인하세요."
    fi

    # 환경 설정 적용 안내
    echo ""
    echo "🚨🚨🚨 [중요] 환경설정을 적용하려면 아래 명령어를 반드시 직접 실행하세요! 🚨🚨🚨"
    echo ""
    echo "    source ~/.zshrc"
    echo ""
    echo "또는 터미널을 완전히 재시작해도 적용됩니다."
    echo ""

    echo "현재 사용 중인 Node.js 버전: $(node -v | sed 's/v//')"
fi