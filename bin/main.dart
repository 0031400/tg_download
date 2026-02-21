import 'dart:async';
import 'dart:io';
import 'package:tdjsonapi/tdjsonapi.dart' as tdlibapi;
import 'package:tdlibjson/tdlibjson.dart' as tdlibjson;
import 'package:dart_telegram_bot/telegram_entities.dart' as tg_bot_entities;
import 'package:dart_telegram_bot/dart_telegram_bot.dart' as tg_bot;
import 'package:path/path.dart';
import 'tdlib_init_auth.dart';
import 'package:http/http.dart';

void main(List<String> arguments) async {
  final botToken = Platform.environment['BotToken']!;
  final apiId = int.parse(Platform.environment['ApiId']!);
  final apiHash = Platform.environment['ApiHash']!;
  final groupName = Platform.environment['GroupName']!;
  final tdlibPath = Platform.environment['TdlibPath']!;
  final newOldFileMap = <String, String>{};
  final deleteAfterUpload = bool.parse(
    Platform.environment['DeleteAfterUpload']!,
  );
  tdlibapi.TdJson.init(tdlibPath: tdlibPath);
  int clientId = tdlibapi.TdJson.tdCreateClientId!();
  final client = tdlibapi.Client(clientId: clientId);
  tdlibapi.TdJson.send(clientId, {
    '@type': 'setLogVerbosityLevel',
    'new_verbosity_level': 1,
  });
  final fileMap = <int, (int, int)>{};
  final uploadLock = <int, bool>{};
  final downloadLock = <int, bool>{};
  client.start(tdlibPath: tdlibPath);
  await tdlibInitAuth(client, apiId, apiHash);
  final res = await client.send({
    '@type': 'searchPublicChat',
    'username': groupName,
  });
  final chatId = tdlibjson.Chat.fromJson(res).id;
  final bot = tg_bot.Bot(token: botToken);
  client.updates.listen((data) async {
    if ((data['@type'] as String) == 'updateFile') {
      final file = tdlibjson.File.fromJson(
        data['file'] as Map<String, dynamic>,
      );
      final fileId = file.id;
      if (fileMap.containsKey(fileId)) {
        if (file.remote.isUploadingCompleted) {
          fileMap.remove(fileId);
          uploadLock.remove(fileId);
        } else {
          if (uploadLock[fileId] ?? false) {
            return;
          }
          uploadLock[fileId] = true;
          try {
            await bot.editMessageText(
              "上传进度 ${(file.remote.uploadedSize / file.size * 100).toStringAsFixed(2)}%",
              tg_bot_entities.ChatID(fileMap[fileId]!.$1),
              fileMap[fileId]!.$2,
            );
          } catch (_) {}
          uploadLock[fileId] = false;
        }
      }
    } else if ((data['@type'] as String) == 'updateMessageSendSucceeded') {
      final message = tdlibjson.Message.fromJson(
        data['message'] as Map<String, dynamic>,
      );
      String p = '';
      if (message.content is tdlibjson.MessageAudio) {
        final content = message.content as tdlibjson.MessageAudio;
        p = content.audio.audio.local.path;
      } else if (message.content is tdlibjson.MessageVideo) {
        final content = message.content as tdlibjson.MessageVideo;
        p = content.video.video.local.path;
      } else {
        return;
      }
      if (p.isNotEmpty) {
        final f = File(p);
        if (f.existsSync()) {
          f.deleteSync();
        }
      }
      if (deleteAfterUpload && newOldFileMap.containsKey(basename(p))) {
        try {
          File(newOldFileMap[basename(p)]!).deleteSync();
        } catch (_) {}
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
    if (update.message?.video != null) {
      await get(
        Uri.parse(
          "https://api.telegram.org/bot$botToken/sendVideo?chat_id=${update.message!.caption!}&video=${update.message!.video!.fileId}",
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
    if ((content is! tdlibjson.MessageAudio) &&
        (content is! tdlibjson.MessageVideo)) {
      return;
    }
    int fileId;
    bool isVideo = false;
    if (content is tdlibjson.MessageAudio) {
      fileId = content.audio.audio.id;
    } else if (content is tdlibjson.MessageVideo) {
      fileId = content.video.video.id;
      isVideo = true;
    } else {
      return;
    }
    final msg = await bot.sendMessage(
      tg_bot_entities.ChatID(update.message!.chat.id),
      "下载进度 0.00%",
    );
    await client.send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': 1,
    });
    Timer.periodic(Duration(milliseconds: 500), (Timer timer) async {
      final res = await client.send({'@type': 'getFile', 'file_id': fileId});
      final file = tdlibjson.File.fromJson(res);
      if (file.local.isDownloadingCompleted) {
        timer.cancel();
        final tempDir = Directory("temp");
        tempDir.createSync();
        final baseName = basename(file.local.path);
        final targetPath = join(tempDir.path, baseName);
        File(file.local.path).copySync(targetPath);
        tdlibjson.File? uploadedFile;
        if (isVideo) {
          final res = await client.send({
            '@type': 'sendMessage',
            'chat_id': chatId,
            'input_message_content': {
              '@type': 'inputMessageVideo',
              'video': {'@type': 'inputFileLocal', 'path': targetPath},
              'caption': {
                '@type': 'formattedText',
                'text': update.message!.chat.id.toString(),
              },
            },
          });
          uploadedFile = tdlibjson.File.fromJson(
            res['content']['video']['video'],
          );
        } else {
          final res = await client.send({
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
          uploadedFile = tdlibjson.File.fromJson(
            res['content']['audio']['audio'],
          );
        }
        newOldFileMap[baseName] = file.local.path;
        fileMap[uploadedFile.id] = (update.message!.chat.id, msg.messageId);
      }
      if (downloadLock[file.id] ?? false) {
        return;
      }
      downloadLock[file.id] = true;
      final downloadedSize = file.local.downloadedSize;
      final totalSize = file.size;
      final progress = downloadedSize / totalSize * 100;
      final newText = "下载进度 ${progress.toStringAsFixed(2)}%";
      try {
        await bot.editMessageText(
          newText,
          tg_bot_entities.ChatID(update.message!.chat.id),
          msg.messageId,
        );
      } catch (_) {}
      downloadLock[file.id] = false;
    });
  });
  bot.start();
  return;
}
