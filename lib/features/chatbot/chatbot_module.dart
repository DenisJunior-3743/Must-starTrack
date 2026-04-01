import '../../data/remote/gemini_service.dart';
import '../../core/di/injection_container.dart';
import 'data/chatbot_repository.dart';
import 'screens/chatbot_screen.dart';

class ChatbotModule {
  ChatbotModule._();

  static ChatbotRepository buildRepository() {
    return ChatbotRepository.defaultForApp(
      geminiService: sl<GeminiService>(),
    );
  }

  static ChatbotScreen buildScreen() {
    return ChatbotScreen(repository: buildRepository());
  }
}
