import 'package:tdjsonapi/tdjsonapi.dart' as tdlibapi;
import 'dart:io';

Future<void> tdlibInitAuth(
  tdlibapi.Client client,
  int apiId,
  String apiHash,
) async {
  while (true) {
    final authState = await client.send({'@type': 'getAuthorizationState'});
    final authorizationState = authState['@type'] as String;
    switch (authorizationState) {
      case "authorizationStateWaitTdlibParameters":
        await client.send({
          '@type': 'setTdlibParameters',
          'database_directory': "data",
          'use_file_database': true,
          'api_id': apiId,
          'api_hash': apiHash,
          'system_language_code': 'zh-cn',
          'device_model': 'flutter',
          'application_version': '1.0.0',
        });
        break;
      case "authorizationStateWaitCode":
        stdout.write("请输入代码：");
        final code = stdin.readLineSync()?.trim() ?? "";
        await client.send({'@type': 'checkAuthenticationCode', 'code': code});
        break;
      case 'authorizationStateWaitPhoneNumber':
        stdout.write("请输入电话号码：");
        final phoneNumber = stdin.readLineSync()?.trim() ?? "";
        await client.send({
          '@type': 'setAuthenticationPhoneNumber',
          'phone_number': phoneNumber,
        });
        break;
      case 'authorizationStateWaitPassword':
        stdout.write("请输入密码：");
        final password = stdin.readLineSync()?.trim() ?? "";
        await client.send({
          '@type': 'checkAuthenticationPassword',
          'password': password,
        });
        break;
      case 'authorizationStateReady':
        print("登录成功");
        return;
    }
  }
}
