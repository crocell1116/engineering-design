import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

class FABPage extends StatefulWidget {
  final Function(int r, int g, int b)? onColorChange;

  const FABPage({super.key, this.onColorChange});

  @override
  State<FABPage> createState() => _FABPageState();
}

class _FABPageState extends State<FABPage> with SingleTickerProviderStateMixin {
  // -------------------------------------------------------
  // [상태 변수 선언]
  // -------------------------------------------------------

  bool _isFabOpen = false;
  bool _isChatBoxOpen = false;
  String _pressedFab = '';

  // STT & TTS 객체
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  // 음성 관련 상태
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastWords = "";
  String _aiResponseText = "";

  // 채팅 관련 객체
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _chatHistory = [];
  bool _isLoading = false;

  /*사용시 같은 네트워크에 있어야 함.*/
  final String _voiceUrl =
      "https://port-0-engineering-design-mi866upaa674bc90.sel3.cloudtype.app/AI";

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    _flutterTts.stop();
    _speechToText.stop();
    super.dispose();
  }

  // -------------------------------------------------------
  // [초기화 로직]
  // -------------------------------------------------------
  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize();
    } catch (e) {
      debugPrint("STT 초기화 실패: $e");
    }
    if (mounted) setState(() {});
  }

  void _initTts() async {
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.8);
  }

  // -------------------------------------------------------
  // [음성 인식 기능 (STT)]
  // -------------------------------------------------------
  void _startListening(StateSetter dialogSetState) async {
    if (!_speechEnabled) return;

    setState(() {
      _lastWords = "";
      _aiResponseText = "";
      _isListening = true;
    });
    dialogSetState(() {
      _lastWords = "";
      _aiResponseText = "";
      _isListening = true;
    });

    await _speechToText.listen(
      onResult: (SpeechRecognitionResult result) {
        setState(() {
          _lastWords = result.recognizedWords;
        });
        dialogSetState(() {});
      },
      localeId: 'ko_KR',
    );
  }

  void _stopListening(StateSetter dialogSetState) async {
    await _speechToText.stop();
    setState(() {
      _isListening = false;
    });
    dialogSetState(() {
      _isListening = false;
    });

    if (_lastWords.isNotEmpty) {
      _generateAndSpeakResponse(dialogSetState);
    }
  }

  // 음성 다이얼로그 완전히 닫기 (STT & TTS 모두 중지)
  void _closeVoiceDialog(StateSetter dialogSetState) async {
    // 1. STT 중지
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }

    // 2. TTS 중지
    await _flutterTts.stop();

    // 3. 상태 초기화
    setState(() {
      _isListening = false;
      _lastWords = "";
      _aiResponseText = "";
    });
    dialogSetState(() {
      _isListening = false;
    });

    debugPrint("🔇 음성 인식 및 TTS 완전히 중지됨");
  }

  // -------------------------------------------------------
  // [서버 통신 및 음성 응답 (TTS)]
  // -------------------------------------------------------
  void _generateAndSpeakResponse(StateSetter dialogSetState) async {
    String userInput = _lastWords;
    String aiResponse = "";

    setState(() => _aiResponseText = "AI가 생각 중입니다...");
    dialogSetState(() => _aiResponseText = "AI가 생각 중입니다...");

    try {
      debugPrint("서버 요청 시작: $_voiceUrl");
      debugPrint("사용자 입력: $userInput");

      final response = await http
          .post(
            Uri.parse(_voiceUrl),
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode({'message': userInput}),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint("서버 응답 코드: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        aiResponse = data['text'] ?? '';
        final functionCalls = data['function_calls'] as List<dynamic>?;
        if (functionCalls != null && functionCalls.isNotEmpty) {
          _handleFunctionCalls(functionCalls);
        }
      } else {
        aiResponse = "서버 오류: ${response.statusCode}";
      }
    } on TimeoutException catch (e) {
      debugPrint("타임아웃 에러: $e");
      aiResponse = "서버 응답 시간 초과. 서버가 실행 중인지 확인해주세요.";
    } on SocketException catch (e) {
      debugPrint("네트워크 에러: $e");
      aiResponse = "서버에 연결할 수 없습니다. URL과 네트워크를 확인해주세요.";
    } catch (e) {
      debugPrint("알 수 없는 에러: $e");
      aiResponse = "서버 연결 실패: ${e.toString()}";
    }

    if (mounted) {
      setState(() => _aiResponseText = aiResponse);
      dialogSetState(() => _aiResponseText = aiResponse);
    }

    if (!aiResponse.contains("서버") && !aiResponse.contains("실패")) {
      _speak(aiResponse);
    }
  }

  void _speak(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.speak(text);
    }
  }

  void _handleFunctionCalls(List<dynamic> calls) {
    for (var call in calls) {
      if (call['function'] == 'set_rgb_color') {
        int r = call['parameters']['r'];
        int g = call['parameters']['g'];
        int b = call['parameters']['b'];

        if (widget.onColorChange != null) {
          widget.onColorChange!(r, g, b);
        }
      }
    }
    debugPrint("함수 호출 감지: $calls");
  }

  // -------------------------------------------------------
  // [UI: 음성 다이얼로그]
  // -------------------------------------------------------
  void _openMicDialog() {
    setState(() {
      _lastWords = "";
      _aiResponseText = "";
      _isFabOpen = false;
    });

    showDialog(
      context: context,
      barrierDismissible: false, // 외부 터치로 닫기 방지
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Center(child: Text('음성 인식')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isListening
                    ? 'AI가 듣는 중...'
                    : (_aiResponseText.isNotEmpty
                          ? _aiResponseText
                          : "버튼을 눌러 말하세요"),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _aiResponseText.isNotEmpty
                      ? Colors.blue
                      : Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  _isListening
                      ? _stopListening(dialogSetState)
                      : _startListening(dialogSetState);
                },
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: _isListening ? Colors.red : Colors.blue,
                  child: Icon(
                    _isListening ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () {
                  // 모든 음성 기능 중지 후 다이얼로그 닫기
                  _closeVoiceDialog(dialogSetState);
                  Navigator.pop(context);
                },
                child: const Text('닫기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // [UI: 채팅 메시지 전송]
  // -------------------------------------------------------
  void _sendChatMessage() async {
    String userInput = _chatController.text.trim();
    if (userInput.isEmpty || _isLoading) return;

    setState(() {
      _chatHistory.add({'role': 'user', 'text': userInput});
      _isLoading = true;
    });
    _chatController.clear();
    _scrollToBottom();

    try {
      debugPrint("채팅 서버 요청: $_voiceUrl");
      debugPrint("메시지: $userInput");

      final response = await http
          .post(
            Uri.parse(_voiceUrl),
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode({'message': userInput}),
          )
          .timeout(const Duration(seconds: 15));

      String aiResponse = "";
      debugPrint("채팅 응답 코드: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        aiResponse = data['text'] ?? '응답 없음';

        final functionCalls = data['function_calls'] as List<dynamic>?;
        if (functionCalls != null && functionCalls.isNotEmpty) {
          _handleFunctionCalls(functionCalls);
        }
      } else {
        aiResponse = "서버 오류: ${response.statusCode}";
      }

      if (mounted) {
        setState(() {
          _chatHistory.add({'role': 'ai', 'text': aiResponse});
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } on TimeoutException catch (e) {
      debugPrint("채팅 타임아웃: $e");
      if (mounted) {
        setState(() {
          _chatHistory.add({'role': 'ai', 'text': "서버 응답 시간 초과"});
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } on SocketException catch (e) {
      debugPrint("채팅 네트워크 에러: $e");
      if (mounted) {
        setState(() {
          _chatHistory.add({'role': 'ai', 'text': "서버 연결 실패: 네트워크를 확인해주세요"});
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("채팅 알 수 없는 에러: $e");
      if (mounted) {
        setState(() {
          _chatHistory.add({'role': 'ai', 'text': "통신 에러: ${e.toString()}"});
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // -------------------------------------------------------
  // [UI: 메인 화면 Build (Stack 사용)]
  // -------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final bool mainPressed = _pressedFab == 'main';

    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final topPadding = mediaQuery.padding.top;

    const double desiredWidth = 275.0;
    const double desiredHeight = 500.0;

    final double maxWidth = screenWidth - 80 - 16;
    final double maxHeight = screenHeight - 80 - topPadding - 16;

    final double containerWidth = math.min(desiredWidth, maxWidth);
    final double containerHeight = math.min(desiredHeight, maxHeight);

    return SizedBox(
      width: screenWidth,
      height: screenHeight,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // 1. 배경 터치 시 메뉴 닫기
            GestureDetector(
              onTap: () {
                if (_isFabOpen) {
                  setState(() {
                    _isFabOpen = false;
                    _isChatBoxOpen = false;
                  });
                }
              },
            ),

            // 2. Floating 메뉴 (채팅, 음성 버튼)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              bottom: 80,
              right: 16,
              child: IgnorePointer(
                ignoring: !_isFabOpen,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _isFabOpen ? 1 : 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildFabOption(Icons.chat, '채팅', Colors.grey[800]!, () {
                        setState(() => _isChatBoxOpen = !_isChatBoxOpen);
                      }),
                      const SizedBox(height: 10),
                      _buildFabOption(Icons.mic, '음성', Colors.grey[800]!, () {
                        _openMicDialog();
                      }),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),

            // 3. 채팅창
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              bottom: 80,
              right: 80,
              child: IgnorePointer(
                ignoring: !(_isFabOpen && _isChatBoxOpen),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _isFabOpen && _isChatBoxOpen ? 1 : 0,
                  child: Container(
                    width: containerWidth,
                    height: containerHeight,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildChatInterface(),
                    ),
                  ),
                ),
              ),
            ),

            // 4. 메인 Floating Action Button
            Positioned(
              bottom: 16,
              right: 16,
              child: Listener(
                onPointerDown: (_) => setState(() => _pressedFab = 'main'),
                onPointerUp: (_) async {
                  await Future.delayed(const Duration(milliseconds: 150));
                  setState(() => _pressedFab = '');

                  final bool shouldOpen = !_isFabOpen;
                  setState(() {
                    _isFabOpen = shouldOpen;
                    if (!shouldOpen) _isChatBoxOpen = false;
                  });
                },
                child: FloatingActionButton(
                  heroTag: 'main',
                  backgroundColor: mainPressed ? Colors.grey : Colors.grey[800],
                  onPressed: () {},
                  child: Icon(
                    _isFabOpen ? Icons.close : Icons.add,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // [Widget: 작은 메뉴 버튼]
  // -------------------------------------------------------
  Widget _buildFabOption(
    IconData icon,
    String label,
    Color color,
    VoidCallback onPressed,
  ) {
    return GestureDetector(
      onTap: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            width: 56,
            height: 56,
            child: Icon(icon, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------
  // [Widget: 채팅 인터페이스 내부]
  // -------------------------------------------------------
  Widget _buildChatInterface() {
    return Column(
      children: [
        // 헤더
        Container(
          height: 44.0,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          decoration: BoxDecoration(color: Colors.grey[200]),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 40),
              const Text(
                'AI 채팅',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.close, color: Colors.black54, size: 20),
                onPressed: () {
                  setState(() => _isChatBoxOpen = false);
                },
              ),
            ],
          ),
        ),
        // 메시지 리스트
        Expanded(
          child: _chatHistory.isEmpty
              ? const Center(
                  child: Text("", style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8.0),
                  itemCount: _chatHistory.length + (_isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _chatHistory.length && _isLoading) {
                      return _buildLoadingIndicator();
                    }
                    final chat = _chatHistory[index];
                    final isMe = chat['role'] == 'user';

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 8.0,
                        ),
                        constraints: const BoxConstraints(maxWidth: 200),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue[100] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                        child: Text(
                          chat['text']!,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        // 입력창
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(
              top: BorderSide(color: Colors.grey[300]!, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Theme(
                  data: ThemeData(
                    textSelectionTheme: TextSelectionThemeData(
                      cursorColor: Colors.blue,
                      selectionColor: Colors.blue.withOpacity(0.3),
                      selectionHandleColor: Colors.blue,
                    ),
                  ),
                  child: TextField(
                    cursorColor: Colors.blue,
                    controller: _chatController,
                    enabled: !_isLoading,
                    style: const TextStyle(color: Colors.black87, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _isLoading ? 'AI가 응답 중...' : '메시지 입력...',
                      hintStyle: const TextStyle(color: Colors.black45),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _sendChatMessage(),
                  ),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.send,
                  color: _isLoading ? Colors.grey : Colors.blue[600],
                ),
                onPressed: _isLoading ? null : _sendChatMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 로딩부분
  Widget _buildLoadingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
          ),
        ),
      ),
    );
  }
}
