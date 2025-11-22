# ==========================================================
# 1. Flutter 필수 규칙 (기본)
# ==========================================================
# Flutter 엔진 및 플러그인 동작을 위해 필수적으로 유지해야 합니다.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.common.** { *; }

# ==========================================================
# 2. 블루투스 (flutter_blue_plus) 및 통신 데이터 보호
# ==========================================================
# 블루투스 라이브러리 코드 유지
-keep class com.boskokg.flutter_blue_plus.** { *; }

# ★ 중요: 데이터 통신에 쓰이는 Protobuf 클래스가 삭제되면 스캔이 안 됩니다.
-keep class com.google.protobuf.** { *; }
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }

# ==========================================================
# 3. 음성 인식 (speech_to_text) 보호
# ==========================================================
# 음성 인식 라이브러리가 삭제되면 초기화 실패로 버튼 터치가 안 됩니다.
-keep class com.csdcorp.lib.android.speech.** { *; }

# ==========================================================
# 4. 안드로이드 시스템 및 일반 보호
# ==========================================================
# 안드로이드 블루투스 및 위치 관련 기본 클래스 보호
-keep class android.bluetooth.** { *; }
-keep class android.location.** { *; }

# Enum(열거형) 타입이 난독화로 이름이 바뀌는 것을 방지
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ==========================================================
# 5. 빌드 에러 방지 (불필요한 경고 무시)
# ==========================================================
# 구글 플레이 기능(분할 설치)이 없어서 생기는 R8 에러를 무시합니다.
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn com.google.protobuf.**