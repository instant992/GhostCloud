import 'dart:io';

import 'package:foxcloud/plugins/app.dart';
import 'package:foxcloud/state.dart';

class Android {
  Future<void> init() async {
    app?.onExit = () async {
      await globalState.appController.savePreferences();
    };
  }
}

final android = Platform.isAndroid ? Android() : null;
