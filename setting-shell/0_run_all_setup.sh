#!/bin/bash

# 에러 발생 시 즉시 종료
set -e

# 에러 처리 함수
handle_error() {
    echo "❌ 오류가 발생했습니다: $1"
    exit 1
}

trap 'handle_error "$BASH_COMMAND"' ERR

echo "=========================================="
echo "🛠️  전체 개발환경 자동 세팅을 시작합니다"
echo "=========================================="
echo ""

# 스크립트 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_BASE_DIR="$HOME/workspace/project"
cd "$SCRIPT_DIR" || handle_error "스크립트 디렉토리로 이동 실패"

# 1. 프로젝트명 입력 및 전체 경로 변수 설정
read -p "생성할 프로젝트명을 입력하세요: " PROJECT_NAME

if [ -z "$PROJECT_NAME" ]; then
    handle_error "프로젝트명이 입력되지 않았습니다."
fi

# 프로젝트 디렉토리 경로 설정
PROJECT_DIR="$TARGET_BASE_DIR/$PROJECT_NAME"

echo "프로젝트 디렉토리: $PROJECT_DIR"

# 디렉토리 존재 여부 확인
if [ ! -d "$PROJECT_DIR" ]; then
    echo "⚠️ 프로젝트 디렉토리가 존재하지 않습니다. 이후 스크립트에서 생성될 수 있습니다."
else
    echo "✅ 프로젝트 디렉토리가 이미 존재합니다."
fi

echo ""
echo "=========================================="
echo "1️⃣ GitHub 리포지토리 클론 및 초기 설정 (eGovFramework MSA 교육용)"
echo "=========================================="
{ echo "$PROJECT_NAME" | bash ./1_clone_github_setting.sh && wait; } || exit 1

echo ""
echo "=========================================="
echo "2️⃣ 인프라 환경 설정 (MySQL, RabbitMQ, Zipkin, ELK)"
echo "=========================================="
{ echo "$PROJECT_NAME" | bash ./2_setup_infra.sh && wait; } || exit 1

echo ""
echo "=========================================="
echo "3️⃣ NVM 및 Node.js 멀티버전 환경 구성 (14.8.0, 16.20.0, 18.19.0)"
echo "=========================================="
{ bash ./3_setup_nvm_and_node.sh && wait; } || exit 1

echo ""
echo "=========================================="
echo "✅ 전체 개발환경 자동 세팅이 완료되었습니다!"
echo "프로젝트 디렉토리: $PROJECT_DIR" 