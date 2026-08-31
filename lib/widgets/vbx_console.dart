import 'package:flutter/material.dart';
import 'package:xterm2/xterm.dart';

import '../services/terminal_service.dart';

class VbxConsole extends StatefulWidget {
  final bool isDark;
  final double fontSize;

  const VbxConsole({super.key, required this.isDark, required this.fontSize});

  @override
  State<VbxConsole> createState() => _VbxConsoleState();
}

class _VbxConsoleState extends State<VbxConsole> {
  late final Terminal _terminal;
  late final VbxTerminalService _terminalService;
  late final FocusNode _terminalFocusNode;

  @override
  void initState() {
    super.initState();

    _terminal = Terminal(maxLines: 10000);
    _terminalService = VbxTerminalService();
    _terminalFocusNode = FocusNode();

    //_terminal.onOutput = (data) {
    // _terminalService.write(data);
    // };

    _startTerminal();
  }

  Future<void> _startTerminal() async {
    await _terminalService.start(_terminal);

    if (!mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _terminalFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _terminalService.dispose();
    _terminal.dispose();
    _terminalFocusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? Colors.black : Colors.grey.shade100,
      child: TerminalView(
        _terminal,
        focusNode: _terminalFocusNode,
        textStyle: const TerminalStyle(fontFamily: 'Consolas', fontSize: 13),
        theme: isDark
            ? TerminalTheme(
                cursor: Colors.white,
                selection: Colors.grey,
                foreground: Colors.white,
                background: Colors.black,
                black: Colors.black,
                red: Colors.red,
                green: Colors.green,
                yellow: Colors.yellow,
                blue: Colors.blue,
                magenta: Colors.purple,
                cyan: Colors.cyan,
                white: Colors.white,
                brightBlack: Colors.grey,
                brightRed: Colors.redAccent,
                brightGreen: Colors.greenAccent,
                brightYellow: Colors.yellowAccent,
                brightBlue: Colors.blueAccent,
                brightMagenta: Colors.purpleAccent,
                brightCyan: Colors.cyanAccent,
                brightWhite: Colors.white,
                searchHitBackground: Colors.yellow,
                searchHitBackgroundCurrent: Colors.orange,
                searchHitForeground: Colors.black,
              )
            : TerminalTheme(
                cursor: Colors.black,
                selection: Colors.grey.shade300,
                foreground: Colors.black,
                background: Colors.grey.shade100,
                black: Colors.black,
                red: Colors.red,
                green: Colors.green,
                yellow: Colors.orange,
                blue: Colors.blue,
                magenta: Colors.purple,
                cyan: Colors.cyan,
                white: Colors.white,
                brightBlack: Colors.grey,
                brightRed: Colors.redAccent,
                brightGreen: Colors.green,
                brightYellow: Colors.orangeAccent,
                brightBlue: Colors.blueAccent,
                brightMagenta: Colors.purpleAccent,
                brightCyan: Colors.cyanAccent,
                brightWhite: Colors.white,
                searchHitBackground: Colors.yellow.shade300,
                searchHitBackgroundCurrent: Colors.orange.shade300,
                searchHitForeground: Colors.black,
              ),
      ),
    );
  }
}
