import 'package:foxcloud/common/file_logger.dart';
import 'package:foxcloud/models/models.dart';
import 'package:foxcloud/state.dart';
import 'package:flutter/cupertino.dart';

class CommonPrint {

  factory CommonPrint() {
    _instance ??= CommonPrint._internal();
    return _instance!;
  }

  CommonPrint._internal();
  static CommonPrint? _instance;

  void log(String? text) {
    final payload = "[GhostCloud] $text";
    debugPrint(payload);
    
    // Write to file log
    fileLogger.log(payload);
    
    if (!globalState.isInit) {
      return;
    }
    globalState.appController.addLog(
      Log.app(payload),
    );
  }
}

final commonPrint = CommonPrint();
