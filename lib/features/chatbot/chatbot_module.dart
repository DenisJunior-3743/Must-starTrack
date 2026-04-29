import '../../data/remote/openai_service.dart';
import '../../core/di/injection_container.dart';
import 'data/chatbot_repository.dart';
import 'screens/chatbot_screen.dart';

class ChatbotModule {
  ChatbotModule._();

  static ChatbotRepository buildRepository() {
    return ChatbotRepository.defaultForApp(
      openAiService: sl<OpenAiService>(),
    );
  }

  static ChatbotScreen buildScreen() {
    return ChatbotScreen(repository: buildRepository());
  }
}
