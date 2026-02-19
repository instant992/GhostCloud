import 'package:foxcloud/common/common.dart';
import 'package:foxcloud/enum/enum.dart';
import 'package:foxcloud/providers/app.dart';
import 'package:foxcloud/providers/state.dart';
import 'package:foxcloud/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VpnManager extends ConsumerStatefulWidget {

  const VpnManager({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  ConsumerState<VpnManager> createState() => _VpnContainerState();
}

class _VpnContainerState extends ConsumerState<VpnManager> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(vpnStateProvider, (prev, next) {
      showTip();
    });
  }

  void showTip() {
    debouncer.call(
      FunctionTag.vpnTip,
      () {
        if (ref.read(runTimeProvider.notifier).isStart) {
          globalState.showNotifier(
            appLocalizations.vpnTip,
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
