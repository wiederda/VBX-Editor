import 'dart:async';

import 'package:flutter/material.dart';

import '../services/terminal_service.dart';

class VbxConsole extends StatefulWidget {
const VbxConsole({super.key});

@override
State<VbxConsole> createState() => _VbxConsoleState();
}

class _VbxConsoleState extends State<VbxConsole> {
final VbxTerminalService _terminal = VbxTerminalService();
final TextEditingController _inputController = TextEditingController();
final ScrollController _scrollController = ScrollController();

StreamSubscription<String>? _outputSubscription;

String _output = '';

@override
void initState() {
super.initState();

_outputSubscription = _terminal.output.listen((text) {
if (!mounted) {
return;
}

setState(() {
_output += text;
});

_scrollToBottom();
});
}

Future<void> _ensureTerminal() async {
if (_terminal.isRunning) {
return;
}

await _terminal.start();

if (mounted) {
setState(() {});
}
}

void _sendCommand() {
final text = _inputController.text;

if (text.isEmpty) {
_terminal.writeLine('');
return;
}

_terminal.writeLine(text);
_inputController.clear();
}

void _scrollToBottom() {
WidgetsBinding.instance.addPostFrameCallback((_) {
if (!_scrollController.hasClients) {
return;
}

_scrollController.jumpTo(
_scrollController.position.maxScrollExtent,
);
});
}

@override
void dispose() {
_outputSubscription?.cancel();
_inputController.dispose();
_scrollController.dispose();
_terminal.dispose();

super.dispose();
}

@override
Widget build(BuildContext context) {
final isDark = Theme.of(context).brightness == Brightness.dark;

return Container(
color: isDark ? Colors.black : Colors.grey.shade100,
child: Column(
children: [
Expanded(
child: SingleChildScrollView(
controller: _scrollController,
padding: const EdgeInsets.all(8),
child: Align(
alignment: Alignment.topLeft,
child: SelectableText(
_output,
style: TextStyle(
fontFamily: 'Consolas',
fontSize: 13,
color: isDark ? Colors.white : Colors.black,
),
),
),
),
),

Container(
padding: const EdgeInsets.symmetric(
horizontal: 8,
vertical: 6,
),
decoration: BoxDecoration(
border: Border(
top: BorderSide(
color: isDark
? Colors.grey.shade800
    : Colors.grey.shade300,
),
),
),
child: Row(
children: [
Expanded(
child: TextField(
controller: _inputController,
style: const TextStyle(
fontFamily: 'Consolas',
fontSize: 13,
),
decoration: const InputDecoration(
hintText: 'Befehl eingeben ...',
border: InputBorder.none,
isDense: true,
),
onTap: _ensureTerminal,
onSubmitted: (_) async {
await _ensureTerminal();
_sendCommand();
},
),
),
IconButton(
tooltip: 'Befehl ausführen',
onPressed: () async {
await _ensureTerminal();
_sendCommand();
},
icon: const Icon(Icons.send),
),
],
),
),
],
),
);
}
}
