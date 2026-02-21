import 'dart:async';
import 'dart:io';
import 'package:tdjsonapi/tdjsonapi.dart' as tdlibapi;
import 'package:tdlibjson/tdlibjson.dart' as tdlibjson;
import 'package:dart_telegram_bot/dart_telegram_bot.dart' as tg_bot;
import 'package:path/path.dart';
import 'tdlib_init_auth.dart';
import 'package:http/http.dart';

void main(List<String> arguments) async {
  final botToken = Platform.environment['BotToken']!;
  final apiId = int.parse(Platform.environment['ApiId']!);
  final apiHash = Platform.environment['ApiHash']!;
  final groupName = Platform.environment['GroupName']!;
  tdlibapi.TdJson.init(tdlibPath: "tdjson.dll");
  int clientId = tdlibapi.TdJson.tdCreateClientId!();
  final client = tdlibapi.Client(clientId: clientId);
  tdlibapi.TdJson.send(clientId, {
    '@type': 'setLogVerbosityLevel',
    'new_verbosity_level': 1,
  });
  client.start(tdlibPath: "tdjson.dll");
  await tdlibInitAuth(client, apiId, apiHash);
  final res = await client.send({
    '@type': 'searchPublicChat',
    'username': groupName,
  });
  final chatId = tdlibjson.Chat.fromJson(res).id;
  final bot = tg_bot.Bot(token: botToken);
  client.updates.listen((data) {
    if ((data['@type'] as String) == 'updateMessageSendSucceeded') {
      final message = tdlibjson.Message.fromJson(
        data['message'] as Map<String, dynamic>,
      );
      if (message.content is tdlibjson.MessageAudio) {
        final content = message.content as tdlibjson.MessageAudio;
        final p = content.audio.audio.local.path;
        if (p.isNotEmpty) {
          File(p).deleteSync();
        }
      }
    }
  });
  bot.onUpdate((bot, update) async {
    if (update.message?.audio != null) {
      await get(
        Uri.parse(
          "https://api.telegram.org/bot$botToken/sendAudio?chat_id=${update.message!.caption!}&audio=${update.message!.audio!.fileId}",
        ),
      );
      return;
    }
    if (!(update.message?.text?.isNotEmpty ?? false)) {
      return;
    }
    if (!(update.message?.entities?.isNotEmpty ?? false)) {
      return;
    }
    final entity = update.message!.entities![0];
    if (entity.type != "url") {
      return;
    }
    final url = update.message!.text!.substring(
      entity.offset,
      entity.offset + entity.length,
    );
    final messageLinkInfo = tdlibjson.MessageLinkInfo.fromJson(
      await client.send({'@type': 'getMessageLinkInfo', 'url': url}),
    );
    final content = messageLinkInfo.message.content;
    if (content is! tdlibjson.MessageAudio) {
      return;
    }
    final fileId = content.audio.audio.id;
    await client.send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': 1,
    });
    Timer.periodic(Duration(milliseconds: 500), (Timer timer) async {
      final file = tdlibjson.File.fromJson(
        await client.send({'@type': 'getFile', 'file_id': fileId}),
      );
      if (file.local.isDownloadingCompleted) {
        timer.cancel();
        final tempDir = Directory("temp");
        tempDir.createSync();
        final baseName = basename(file.local.path);
        final targetPath = join(tempDir.path, baseName);
        File(file.local.path).copySync(targetPath);
        await client.send({
          '@type': 'sendMessage',
          'chat_id': chatId,
          'input_message_content': {
            '@type': 'inputMessageAudio',
            'audio': {'@type': 'inputFileLocal', 'path': targetPath},
            'title': baseName,
            'caption': {
              '@type': 'formattedText',
              'text': update.message!.chat.id.toString(),
            },
          },
        });
      }
    });
  });
  bot.start();
  return;
}
