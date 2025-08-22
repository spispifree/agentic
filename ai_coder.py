#!/usr/bin/env python3
"""
Smart AI Coder - 내 소스코드 재활용 + AI 보완 시스템
사용법: python ai_coder.py "쇼핑몰 사이트 만들어줘"
"""

import os
import sys
import json
import yaml
import logging
import subprocess
import requests
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
from datetime import datetime

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('logs/ai_coder.log')
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class CodeMatch:
    """코드 매칭 결과"""
    file_path: str
    content: str
    relevance_score: float
    
@dataclass
class Task:
    """작업 정의"""
    id: str
    description: str
    status: str = "pending"  # pending, in_progress, completed, failed
    code_matches: List[CodeMatch] = None
    generated_code: str = ""
    output_path: str = ""

class SmartAICoder:
    def __init__(self, config_path: str = "config.yaml"):
        """초기화"""
        self.config = self._load_config(config_path)
        self.tasks: List[Task] = []
        os.makedirs("logs", exist_ok=True)
        
    def _load_config(self, config_path: str) -> Dict:
        """설정 파일 로드"""
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                config = yaml.safe_load(f)
            
            # 환경 변수 치환
            self._substitute_env_vars(config)
            return config
        except Exception as e:
            logger.error(f"설정 파일 로드 실패: {e}")
            sys.exit(1)
    
    def _substitute_env_vars(self, obj):
        """환경 변수 치환 ${VAR_NAME} -> 실제 값"""
        if isinstance(obj, dict):
            for key, value in obj.items():
                obj[key] = self._substitute_env_vars(value)
        elif isinstance(obj, list):
            for i, item in enumerate(obj):
                obj[i] = self._substitute_env_vars(item)
        elif isinstance(obj, str) and obj.startswith("${") and obj.endswith("}"):
            var_name = obj[2:-1]
            return os.getenv(var_name, obj)
        return obj

    def search_existing_code(self, keyword: str) -> List[CodeMatch]:
        """기존 소스코드에서 키워드 검색"""
        matches = []
        base_path = Path(self.config['project']['base_path'])
        
        if not base_path.exists():
            logger.warning(f"소스 디렉토리가 존재하지 않습니다: {base_path}")
            return matches
            
        extensions = self.config['search']['file_extensions']
        exclude_dirs = self.config['search']['exclude_dirs']
        
        for ext in extensions:
            for file_path in base_path.rglob(f"*{ext}"):
                # 제외 디렉토리 체크
                if any(exclude_dir in str(file_path) for exclude_dir in exclude_dirs):
                    continue
                    
                try:
                    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                        
                    # 키워드 매칭 점수 계산
                    keyword_lower = keyword.lower()
                    content_lower = content.lower()
                    
                    score = 0
                    if keyword_lower in content_lower:
                        score += content_lower.count(keyword_lower) * 10
                        
                    # 파일명 매칭 보너스
                    if keyword_lower in file_path.name.lower():
                        score += 50
                        
                    # 클래스명/함수명 매칭 체크 (간단 버전)
                    if f"class {keyword}" in content or f"function {keyword}" in content:
                        score += 100
                        
                    if score > 0:
                        matches.append(CodeMatch(
                            file_path=str(file_path),
                            content=content,
                            relevance_score=score
                        ))
                        
                except Exception as e:
                    logger.debug(f"파일 읽기 실패 {file_path}: {e}")
                    
        # 점수 순으로 정렬
        matches.sort(key=lambda x: x.relevance_score, reverse=True)
        return matches[:5]  # 상위 5개만 반환

    def call_ai_model(self, prompt: str) -> str:
        """AI 모델 호출"""
        try:
            ai_config = self.config['ai']
            provider = ai_config['default']
            
            if provider == "local":
                return self._call_ollama(prompt)
            elif provider == "cloud":
                return self._call_cloud_api(prompt)
            else:
                raise ValueError(f"지원하지 않는 AI 제공자: {provider}")
                
        except Exception as e:
            logger.error(f"AI 모델 호출 실패: {e}")
            return f"# AI 호출 실패\n# 오류: {str(e)}\n# 수동으로 구현이 필요합니다."

    def _call_ollama(self, prompt: str) -> str:
        """Ollama 로컬 모델 호출"""
        model = self.config['ai']['local']['model']
        
        try:
            result = subprocess.run(
                ['ollama', 'run', model],
                input=prompt.encode('utf-8'),
                capture_output=True,
                timeout=60
            )
            
            if result.returncode == 0:
                return result.stdout.decode('utf-8')
            else:
                error_msg = result.stderr.decode('utf-8')
                logger.error(f"Ollama 실행 실패: {error_msg}")
                return f"# Ollama 호출 실패\n# 오류: {error_msg}"
                
        except subprocess.TimeoutExpired:
            return "# AI 응답 시간 초과"
        except FileNotFoundError:
            return "# Ollama가 설치되지 않았습니다. 'ollama' 명령어를 찾을 수 없습니다."

    def _call_cloud_api(self, prompt: str) -> str:
        """클라우드 API 호출 (OpenAI/Anthropic)"""
        cloud_config = self.config['ai']['cloud']
        
        if cloud_config['provider'] == 'openai':
            return self._call_openai(prompt, cloud_config)
        else:
            return "# 클라우드 API 호출 미구현"

    def _call_openai(self, prompt: str, config: Dict) -> str:
        """OpenAI API 호출"""
        try:
            headers = {
                'Authorization': f"Bearer {config['api_key']}",
                'Content-Type': 'application/json'
            }
            
            data = {
                'model': config['model'],
                'messages': [{'role': 'user', 'content': prompt}],
                'max_tokens': config.get('max_tokens', 4096),
                'temperature': config.get('temperature', 0.1)
            }
            
            response = requests.post(
                'https://api.openai.com/v1/chat/completions',
                headers=headers,
                json=data,
                timeout=30
            )
            
            if response.status_code == 200:
                result = response.json()
                return result['choices'][0]['message']['content']
            else:
                return f"# OpenAI API 오류 ({response.status_code}): {response.text}"
                
        except Exception as e:
            return f"# OpenAI API 호출 실패: {str(e)}"

    def break_down_request(self, user_request: str) -> List[Task]:
        """사용자 요청을 세부 작업으로 분할"""
        # 간단한 키워드 기반 분할 (나중에 AI로 개선 가능)
        tasks = []
        
        if "쇼핑몰" in user_request or "ecommerce" in user_request.lower():
            tasks = [
                Task("db_design", "데이터베이스 스키마 설계"),
                Task("user_auth", "사용자 인증 API"),
                Task("product_api", "상품 관리 API"),
                Task("cart_api", "장바구니 API"),
                Task("order_api", "주문 처리 API"),
                Task("frontend_product", "상품 목록 페이지"),
                Task("frontend_cart", "장바구니 페이지"),
                Task("deployment", "Docker & 배포 설정")
            ]
        elif "블로그" in user_request or "blog" in user_request.lower():
            tasks = [
                Task("db_design", "블로그 데이터베이스 설계"),
                Task("post_api", "게시글 CRUD API"),
                Task("comment_api", "댓글 기능 API"), 
                Task("frontend_list", "게시글 목록 페이지"),
                Task("frontend_detail", "게시글 상세 페이지"),
                Task("admin_panel", "관리자 페이지")
            ]
        else:
            # 일반적인 작업 분할
            tasks = [Task("general_task", user_request)]
            
        self.tasks = tasks
        return tasks

    def process_task(self, task: Task) -> bool:
        """개별 작업 처리"""
        logger.info(f"작업 시작: {task.description}")
        task.status = "in_progress"
        
        # 1. 기존 코드 검색
        code_matches = self.search_existing_code(task.id)
        task.code_matches = code_matches
        
        if code_matches:
            logger.info(f"✅ 기존 코드 발견: {len(code_matches)}개 파일")
            for match in code_matches[:3]:  # 상위 3개만 로그
                logger.info(f"  - {match.file_path} (점수: {match.relevance_score})")
            
            # 기존 코드가 충분한 경우 재사용
            if code_matches[0].relevance_score > 50:
                task.generated_code = f"# 기존 코드 재사용\n# 파일: {code_matches[0].file_path}\n\n{code_matches[0].content}"
                task.status = "completed"
                return True
        
        # 2. 기존 코드가 없거나 부족한 경우 AI 호출
        logger.info("⚠️ 기존 코드 없음 → AI 호출")
        
        prompt = self._build_ai_prompt(task, code_matches)
        ai_response = self.call_ai_model(prompt)
        
        # 3. 결과 저장
        task.generated_code = ai_response
        task.output_path = f"logs/{task.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.md"
        
        with open(task.output_path, 'w', encoding='utf-8') as f:
            f.write(f"# {task.description}\n\n")
            f.write(f"## 기존 코드 검색 결과\n")
            if code_matches:
                for match in code_matches:
                    f.write(f"- {match.file_path} (점수: {match.relevance_score})\n")
            else:
                f.write("- 관련 코드 없음\n")
            f.write(f"\n## AI 생성 코드\n\n{ai_response}\n")
        
        task.status = "completed"
        logger.info(f"✍️ AI 코드 생성 완료: {task.output_path}")
        return True

    def _build_ai_prompt(self, task: Task, code_matches: List[CodeMatch]) -> str:
        """AI를 위한 프롬프트 구성"""
        tech_stack = self.config['tech_stack']
        
        prompt = f"""다음 작업을 수행해주세요:

작업: {task.description}

기술 스택:
- 프론트엔드: {', '.join(tech_stack['frontend'])}
- 백엔드: {', '.join(tech_stack['backend'])}
- 데이터베이스: {', '.join(tech_stack['database'])}

"""
        
        if code_matches:
            prompt += "기존 관련 코드:\n"
            for i, match in enumerate(code_matches[:2]):  # 상위 2개만 포함
                prompt += f"\n파일 {i+1}: {match.file_path}\n```\n{match.content[:1000]}...\n```\n"
            prompt += "\n위 기존 코드를 참고하여 일관성 있는 스타일로 작성해주세요.\n"
        
        prompt += """
요구사항:
1. 실행 가능한 완전한 코드 작성
2. 주석은 한글로 작성
3. 에러 처리 포함
4. 보안 모범 사례 준수
5. 테스트 가능한 구조

결과물은 마크다운 코드 블록으로 제공해주세요.
"""
        
        return prompt

    def send_notification(self, message: str):
        """완료 알림 전송"""
        if not self.config['notifications']['telegram']['enabled']:
            return
            
        try:
            token = self.config['notifications']['telegram']['bot_token']
            chat_id = self.config['notifications']['telegram']['chat_id']
            
            if not token or not chat_id:
                logger.warning("텔레그램 설정이 불완전합니다")
                return
                
            url = f"https://api.telegram.org/bot{token}/sendMessage"
            data = {
                'chat_id': chat_id,
                'text': message,
                'parse_mode': 'Markdown'
            }
            
            response = requests.post(url, data=data, timeout=10)
            if response.status_code == 200:
                logger.info("텔레그램 알림 전송 완료")
            else:
                logger.warning(f"텔레그램 알림 실패: {response.text}")
                
        except Exception as e:
            logger.error(f"알림 전송 실패: {e}")

    def run(self, user_request: str):
        """메인 실행 함수"""
        logger.info(f"요청 시작: {user_request}")
        
        # 1. 작업 분할
        tasks = self.break_down_request(user_request)
        logger.info(f"총 {len(tasks)}개 작업으로 분할")
        
        # 2. 각 작업 처리
        completed_tasks = []
        failed_tasks = []
        
        for task in tasks:
            try:
                success = self.process_task(task)
                if success:
                    completed_tasks.append(task)
                else:
                    failed_tasks.append(task)
            except Exception as e:
                logger.error(f"작업 실패 {task.description}: {e}")
                task.status = "failed"
                failed_tasks.append(task)
        
        # 3. 결과 요약
        summary = self._build_summary(user_request, completed_tasks, failed_tasks)
        print(summary)
        
        # 4. 알림 전송
        self.send_notification(summary)
        
        logger.info("모든 작업 완료")

    def _build_summary(self, request: str, completed: List[Task], failed: List[Task]) -> str:
        """작업 결과 요약"""
        summary = f"""
🎯 **작업 완료 보고**

**요청**: {request}
**완료 시간**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

✅ **완료된 작업** ({len(completed)}개):
"""
        
        for task in completed:
            reused = "재사용" if task.code_matches and task.code_matches[0].relevance_score > 50 else "AI생성"
            summary += f"• {task.description} ({reused})\n"
            if task.output_path:
                summary += f"  파일: {task.output_path}\n"
        
        if failed:
            summary += f"\n❌ **실패한 작업** ({len(failed)}개):\n"
            for task in failed:
                summary += f"• {task.description}\n"
        
        summary += f"\n📊 **통계**: 성공 {len(completed)}개, 실패 {len(failed)}개"
        return summary


def main():
    """CLI 진입점"""
    if len(sys.argv) != 2:
        print("사용법: python ai_coder.py '작업 요청'")
        print("예시: python ai_coder.py '쇼핑몰 사이트 만들어줘'")
        sys.exit(1)
    
    user_request = sys.argv[1]
    
    try:
        coder = SmartAICoder()
        coder.run(user_request)
    except KeyboardInterrupt:
        print("\n작업이 중단되었습니다.")
        sys.exit(1)
    except Exception as e:
        logger.error(f"예상치 못한 오류: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()