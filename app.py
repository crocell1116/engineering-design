import os
from flask import Flask, request, jsonify
from flask_cors import CORS
import google.generativeai as genai
from dotenv import load_dotenv
import re

# 로컬에서 실행 시 .env 파일 로드
load_dotenv()

app = Flask(__name__)
# CORS 설정
CORS(app)

api_key = os.getenv("GEMINI_API_KEY")
if not api_key:
    raise ValueError("API Key가 설정되지 않았습니다. .env 파일을 확인해주세요.")

genai.configure(api_key=api_key)

# 3. 시스템 프롬프트 설정 (수정됨)
SYSTEM_INSTRUCTION = """당신은 친절한 AI 어시스턴트입니다. 
규칙:
1. 모든 답변은 1~2문장 이내로 짧고 간결하게 답변하세요.
2. 사용자가 색깔을 요청하면 반드시 "RGB(R값, G값, B값)" 형식으로 포함해서 답변하세요.
3. **사용자가 "조명 꺼", "불 꺼" 등을 요청하면 반드시 "RGB(0, 0, 0)"을 포함해서 답변하세요.**
   예: "네, 조명을 끌게요. RGB(0, 0, 0)"
4. 일반 대화는 간단명료하게 답변하세요.

색상 예시:
- 빨강: RGB(255, 0, 0)
- 초록: RGB(0, 255, 0)
- 파랑: RGB(0, 0, 255)
- 노랑: RGB(255, 255, 0)
- 보라: RGB(128, 0, 128)
- 주황: RGB(255, 165, 0)
- 분홍: RGB(255, 192, 203)
- 하양: RGB(255, 255, 255)
- 검정(끄기): RGB(0, 0, 0)
"""

# 모델(Gemini 2.5 Flash)
model = genai.GenerativeModel(
    model_name='gemini-2.5-flash', 
    system_instruction=SYSTEM_INSTRUCTION
)

# 채팅 세션 (대화 문맥 유지)
chat_session = model.start_chat(history=[])

def extract_rgb_from_text(text):
    """텍스트에서 RGB 값 추출"""
    pattern = r'RGB\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)'
    match = re.search(pattern, text, re.IGNORECASE)
    
    if match:
        r, g, b = int(match.group(1)), int(match.group(2)), int(match.group(3))
        # RGB 값 유효성 검사 (0-255 범위)
        if 0 <= r <= 255 and 0 <= g <= 255 and 0 <= b <= 255:
            return {'r': r, 'g': g, 'b': b}
    return None

# 채팅 및 명령 처리
@app.route('/AI', methods=['POST'])
def chat():
    """사용자 메시지를 받아 Gemini 모델에게 전달하고 응답을 반환합니다."""
    try:
        data = request.json
        user_message = data.get('message', '')
        
        if not user_message:
            return jsonify({'text': '메시지를 입력해주세요.', 'function_calls': []}), 200
    
        # Gemini에게 메시지 전송
        response = chat_session.send_message(user_message)
        ai_response = response.text.strip()
    
        # RGB 값 추출 시도
        rgb_values = extract_rgb_from_text(ai_response)
        function_calls = []
        
        # 사용자에게 표시할 텍스트 (기본값은 원본 응답)
        display_text = ai_response

        if rgb_values:
            # RGB(0,0,0)도 정상적인 RGB 값이므로 여기서 걸러져서 클라이언트로 전송됩니다.
            function_calls.append({
                'function': 'set_rgb_color',
                'parameters': rgb_values
            })
            
            # 사용자에게는 RGB 코드를 보여주지 않도록 텍스트에서 제거
            pattern = r'RGB\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)'
            display_text = re.sub(pattern, '', ai_response).strip()
        
        return jsonify({
            'text': display_text,
            'function_calls': function_calls
        }), 200
        
    except Exception as e:
        return jsonify({
            'text': f'오류가 발생했습니다: {str(e)}',
            'function_calls': []
        }), 500

if __name__ == '__main__':
    port = int(os.getenv("PORT") or 5000)
    app.run(port=port, debug=True)