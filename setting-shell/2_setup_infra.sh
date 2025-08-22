#!/bin/bash

# 에러 발생 시 즉시 종료
set -e


# ====== 인자(프로젝트명) 처리 ======
if [ -z "$1" ]; then
    read -p "인프라 및 Java 환경을 세팅할 프로젝트명을 입력하세요: " PROJECT_NAME
    [ -z "$PROJECT_NAME" ] && { echo "❌ 프로젝트명이 입력되지 않았습니다."; exit 1; }
else
    PROJECT_NAME="$1"
fi

# ====== 경로 설정 ======
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_BASE_DIR="$HOME/workspace/project"
PROJECT_DIR="$TARGET_BASE_DIR/$PROJECT_NAME"

# ====== 에러 처리 함수 ======
handle_error() {
    echo "❌ 오류가 발생했습니다: $1"
    exit 1
}

# ====== Docker 실행 상태 확인 함수 ======
check_docker() {
    # Docker Desktop 프로세스 확인
    if ! pgrep -f "Docker Desktop" > /dev/null; then
        echo "Docker Desktop이 실행되지 않았습니다."
        
        # macOS의 경우 Docker Desktop 실행
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "Docker Desktop을 시작합니다..."
            open -a Docker
            
            # Docker 시작 대기
            echo "Docker 시작을 기다리는 중..."
            for i in {1..30}; do
                if docker info >/dev/null 2>&1; then
                    echo "Docker가 성공적으로 시작되었습니다!"
                    return 0
                fi
                echo -n "."
                sleep 2
            done
            
            handle_error "Docker를 시작할 수 없습니다. Docker Desktop이 설치되어 있고 정상적으로 실행되는지 확인해주세요."
        else
            handle_error "Docker 데몬이 실행되지 않았습니다. Docker를 시작해주세요."
        fi
    fi

    # Docker 데몬 연결 확인
    if ! docker info >/dev/null 2>&1; then
        handle_error "Docker 데몬에 연결할 수 없습니다. Docker가 정상적으로 실행 중인지 확인해주세요."
    fi
}

trap 'handle_error "$BASH_COMMAND"' ERR

echo "=========================================="
echo "🛠️  인프라 환경 설정을 시작합니다"
echo "=========================================="

# Docker 실행 상태 확인
echo "Docker 실행 상태 확인 중..."
check_docker

# ====== 프로젝트 디렉토리 체크 및 이동 ======
if [ ! -d "$PROJECT_DIR" ]; then
    handle_error "프로젝트 디렉토리($PROJECT_NAME)가 존재하지 않습니다."
fi

cd "$PROJECT_DIR" || handle_error "프로젝트 디렉토리로 이동할 수 없습니다."

# ====== 기존 컨테이너 및 리소스 정리 ======
echo "기존 리소스 정리 중..."

# 컨테이너 정리
docker rm -f rabbitmq zipkin elasticsearch kibana logstash 2>/dev/null || true

# 사용 중인 포트 확인 및 종료
check_and_kill_port() {
    local port=$1
    local pid=$(lsof -ti:$port)
    if [ ! -z "$pid" ]; then
        echo "포트 $port가 사용 중입니다. 프로세스를 종료합니다..."
        kill -9 $pid
    fi
}

# 포트 확인
check_and_kill_port 3306  # MySQL
check_and_kill_port 5672  # RabbitMQ
check_and_kill_port 15672 # RabbitMQ Management
check_and_kill_port 9411  # Zipkin
check_and_kill_port 9200  # Elasticsearch
check_and_kill_port 5601  # Kibana
check_and_kill_port 5044  # Logstash

# ====== Docker 네트워크 설정 ======
echo "Docker 네트워크 설정 중..."
if ! docker network ls | grep -q "egov-network"; then
    echo "egov-network 생성 중..."
    docker network create egov-network
else
    echo "egov-network가 이미 존재합니다. 기존 네트워크를 사용합니다."
fi

# ====== MySQL 설정 ======
echo "MySQL 설정 중..."
cd docker-compose/mysql
docker-compose down -v 2>/dev/null || true
docker-compose up -d

# ====== RabbitMQ 설정 ======
echo "RabbitMQ 설정 중..."
docker run -d -e TZ=Asia/Seoul --name rabbitmq --network egov-network \
    -p 5672:5672 -p 15672:15672 rabbitmq:management

# ====== Zipkin 설정 ======
echo "Zipkin 설정 중..."
docker run --name zipkin -d --network egov-network \
    -p 9411:9411 -e TZ=Asia/Seoul openzipkin/zipkin

# ====== ELK 스택 설정 ======
echo "ELK 스택 설정 중..."
cd ../elk

# 데이터 디렉토리 생성
mkdir -p ../../../data && chmod -R 770 ../../../data

# 플랫폼 확인
PLATFORM=$(uname -m)
if [ "$PLATFORM" = "arm64" ]; then
    echo "M1/M2 Mac (ARM64) 환경이 감지되었습니다."
    # ARM64용 이미지 설정
    export ELASTIC_IMAGE="docker.elastic.co/elasticsearch/elasticsearch:7.17.10-arm64"
    export KIBANA_IMAGE="docker.elastic.co/kibana/kibana:7.17.10-arm64"
    export LOGSTASH_IMAGE="docker.elastic.co/logstash/logstash:7.17.10-arm64"
else
    # AMD64용 기본 이미지 설정
    export ELASTIC_IMAGE="docker.elastic.co/elasticsearch/elasticsearch:7.17.10"
    export KIBANA_IMAGE="docker.elastic.co/kibana/kibana:7.17.10"
    export LOGSTASH_IMAGE="docker.elastic.co/logstash/logstash:7.17.10"
fi

# ELK 스택 실행
docker-compose down -v 2>/dev/null || true
docker-compose up -d

# ====== 상태 확인 ======
echo "컨테이너 상태 확인 중..."
docker ps

echo ""
echo "=========================================="
echo "✅ 인프라 환경 설정이 완료되었습니다!"
echo "=========================================="
