#!/bin/bash

# ====== 설정 ======
SOURCE_DIR="$HOME/workspace/dev/source-example/egovframe-msa-edu"
TARGET_BASE_DIR="$HOME/workspace/project"

# ====== 경로 설정 ======
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ====== 함수 ======
handle_error() {
    echo "❌ 오류가 발생했습니다: $1"
    exit 1
}

# trap으로 모든 에러를 handle_error로 처리
trap 'handle_error "$BASH_COMMAND"' ERR

# ====== Homebrew 체크 ======
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew가 설치되어 있지 않습니다."
    echo "Homebrew 설치를 진행해주세요: https://brew.sh/"
    exit 1
else
    echo "✅ Homebrew가 이미 설치되어 있습니다. (버전: $(brew --version | head -n 1))"
fi

# ====== GitHub CLI 체크 및 설치 ======
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI(gh)가 설치되어 있지 않습니다. 설치를 시작합니다..."
    brew install gh || handle_error "GitHub CLI 설치에 실패했습니다."
    echo "✅ GitHub CLI 설치가 완료되었습니다."
else
    echo "✅ GitHub CLI가 이미 설치되어 있습니다. (버전: $(gh --version | head -n 1))"
fi

# ====== 프로젝트명 인자/입력 처리 ======
if [ -z "$1" ]; then
    echo "내 GitHub에 생성할 새 프로젝트명을 입력하세요: "
    read PROJECT_NAME
    [ -z "$PROJECT_NAME" ] && handle_error "프로젝트명이 입력되지 않았습니다."
else
    PROJECT_NAME="$1"
fi

# ====== GitHub CLI 인증 확인 ======
if ! gh auth status >/dev/null 2>&1; then
    echo "❌ GitHub CLI 인증이 필요합니다."
    echo "다음 명령어를 실행하여 GitHub에 로그인하세요:"
    echo "   gh auth login"
    echo ""
    echo "로그인 후 이 스크립트를 다시 실행해주세요."
    exit 1
fi

# ====== GitHub 사용자명 확인 ======
GITHUB_USERNAME=$(gh api user --jq '.login') || handle_error "GitHub 사용자명을 가져올 수 없습니다."

# ====== 타겟 디렉토리 생성 ======
mkdir -p "$TARGET_BASE_DIR"

# ====== 리포지토리 존재 여부 확인 ======
if [ -d "$TARGET_BASE_DIR/$PROJECT_NAME" ] && [ -d "$TARGET_BASE_DIR/$PROJECT_NAME/.git" ]; then
    echo "✅ 프로젝트 디렉토리와 Git 리포지토리가 이미 존재합니다. 스크립트를 건너뜁니다."
    exit 0
fi

# ====== GitHub 리포지토리 관리 함수 ======
create_github_repo() {
    local repo_name="$1"
    local max_attempts=3
    local attempt=1
    
    echo "🔨 GitHub 리포지토리 '$repo_name' 생성 프로세스 시작..."
    
    # 리포지토리가 존재하지 않을 때까지 대기 (최대 30초)
    local wait_attempts=6
    local wait_count=0
    while gh repo view "$GITHUB_USERNAME/$repo_name" &>/dev/null; do
        if [ $wait_count -ge $wait_attempts ]; then
            echo "❌ 기존 리포지토리가 여전히 존재합니다. 삭제가 완료되지 않았습니다."
            return 1
        fi
        echo "⏳ 이전 리포지토리 삭제 완료 대기 중... (${wait_count}/${wait_attempts})"
        sleep 5
        wait_count=$((wait_count + 1))
    done
    
    while [ $attempt -le $max_attempts ]; do
        echo "➡️ 생성 시도 #$attempt..."
        if gh repo create "$repo_name" --private; then
            # 생성 확인을 위한 대기
            sleep 3
            if gh repo view "$GITHUB_USERNAME/$repo_name" &>/dev/null; then
                echo "✅ 리포지토리가 성공적으로 생성되었습니다!"
                return 0
            fi
        fi
        
        echo "⏳ 다음 시도 전 5초 대기..."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo "❌ 최대 시도 횟수 초과: 리포지토리 생성 실패"
    return 1
}

delete_github_repo() {
    local repo_name="$1"
    local max_attempts=3
    local attempt=1
    
    echo "🗑️ GitHub 리포지토리 '$repo_name' 삭제 프로세스 시작..."
    
    while [ $attempt -le $max_attempts ]; do
        echo "➡️ 삭제 시도 #$attempt..."
        
        # 리포지토리 존재 여부 확인
        if ! gh repo view "$GITHUB_USERNAME/$repo_name" &>/dev/null; then
            echo "✅ 리포지토리가 이미 삭제되었거나 존재하지 않습니다."
            return 0
        fi
        
        # 리포지토리 삭제 시도
        echo "🗑️ 리포지토리 삭제 명령 실행 중..."
        if gh repo delete "$GITHUB_USERNAME/$repo_name" --yes; then
            echo "✅ 삭제 명령이 실행되었습니다."
            
            # 삭제 확인을 위한 대기 및 확인
            local check_attempts=6
            local check_attempt=1
            
            while [ $check_attempt -le $check_attempts ]; do
                echo "🔍 삭제 확인 중... ($check_attempt/$check_attempts)"
                if ! gh repo view "$GITHUB_USERNAME/$repo_name" &>/dev/null; then
                    echo "✅ 리포지토리가 성공적으로 삭제되었습니다!"
                    return 0
                fi
                echo "⏳ 5초 대기 후 다시 확인합니다..."
                sleep 5
                check_attempt=$((check_attempt + 1))
            done
        else
            echo "⚠️ 삭제 명령 실행 실패 (시도 $attempt/$max_attempts)"
        fi
        
        echo "⏳ 다음 시도 전 5초 대기..."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo "❌ 최대 시도 횟수 초과: 리포지토리 삭제 실패"
    return 1
}

# ====== 내 GitHub에 동일한 리포지토리 존재 여부 확인 및 처리 ======
if gh repo view "$GITHUB_USERNAME/$PROJECT_NAME" &>/dev/null; then
    echo "⚠️ 내 GitHub에 '$PROJECT_NAME' 리포지토리가 이미 존재합니다."
    echo "1) 기존 GitHub 리포지토리 삭제 후 계속 진행"
    echo "2) 다른 프로젝트명으로 다시 시작"
    echo "3) 스크립트 종료"
    read -p "선택해주세요 (1/2/3): " repo_choice
    case $repo_choice in
        1)
        echo "기존 GitHub 리포지토리를 삭제합니다..."
        gh repo delete "$GITHUB_USERNAME/$PROJECT_NAME" --yes || handle_error "리포지토리 삭제에 실패했습니다."
        ;;
    2)
        echo "스크립트를 다시 실행해주세요."
        exit 0
        ;;
    3)
        echo "스크립트를 종료합니다."
        exit 0
        ;;
    *)
        handle_error "잘못된 선택입니다."
        ;;
    esac
fi

# ====== 로컬 폴더 존재 여부 확인 및 처리 ======
if [ -d "$TARGET_BASE_DIR/$PROJECT_NAME" ]; then
    echo "⚠️ '$TARGET_BASE_DIR/$PROJECT_NAME' 폴더가 이미 존재합니다."
    echo "1) 기존 폴더 삭제 후 계속 진행"
    echo "2) 다른 프로젝트명으로 다시 시작"
    echo "3) 스크립트 종료"
    read -p "선택해주세요 (1/2/3): " folder_choice
    case $folder_choice in
        1)
            echo "기존 폴더를 삭제합니다..."
            rm -rf "$TARGET_BASE_DIR/$PROJECT_NAME"
                ;;
            2)
                echo "스크립트를 다시 실행해주세요."
                exit 0
                ;;
            3)
                echo "스크립트를 종료합니다."
                exit 0
                ;;
        *)
            handle_error "잘못된 선택입니다."
            ;;
    esac
fi

# ====== 소스 디렉토리에서 최신 소스 가져오기 ======
echo "원본 소스 디렉토리에서 최신 소스 가져오기..."
if [ ! -d "$SOURCE_DIR" ]; then
    handle_error "소스 디렉토리가 존재하지 않습니다: $SOURCE_DIR"
fi

cd "$SOURCE_DIR" || handle_error "소스 디렉토리로 이동할 수 없습니다."
echo "git pull 실행 중..."
git pull || handle_error "git pull에 실패했습니다."

# ====== 소스 디렉토리를 프로젝트 디렉토리로 복사 ======
echo "소스 디렉토리를 '$TARGET_BASE_DIR/$PROJECT_NAME'로 복사 중..."
cp -r "$SOURCE_DIR" "$TARGET_BASE_DIR/$PROJECT_NAME" || handle_error "디렉토리 복사에 실패했습니다."

# ====== 복사된 디렉토리로 이동 ======
cd "$TARGET_BASE_DIR/$PROJECT_NAME" || handle_error "프로젝트 디렉토리로 이동할 수 없습니다."

# ====== 내 GitHub에 새 리포지토리 생성 ======
echo "내 GitHub에 새 리포지토리 '$PROJECT_NAME' 생성 중..."
gh repo create "$PROJECT_NAME" --private || handle_error "GitHub 리포지토리 생성에 실패했습니다."

# ====== 리모트 URL을 내 GitHub로 변경 ======
echo "리모트(origin) URL을 내 GitHub 리포지토리로 변경 중..."
git remote remove origin || handle_error "기존 origin 삭제에 실패했습니다."
git remote add origin "git@github.com:$GITHUB_USERNAME/$PROJECT_NAME.git" || handle_error "새 origin 추가에 실패했습니다."

# ====== 내 GitHub에 푸시 ======
echo "내 GitHub 리포지토리에 소스 푸시 중..."
git push -u origin main || git push -u origin master || handle_error "GitHub에 푸시에 실패했습니다."

echo "✅ 모든 작업이 성공적으로 완료되었습니다!"
echo "내 GitHub 리포지토리: https://github.com/$GITHUB_USERNAME/$PROJECT_NAME" 