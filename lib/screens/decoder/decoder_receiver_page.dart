import 'package:flutter/material.dart';

import '../../services/webrtc_mirror_service.dart';
import '../../theme/app_theme.dart';
import 'decoder_common.dart';
import 'decoder_qr_scan_page.dart';

class DecoderReceiverPage extends StatefulWidget {
  const DecoderReceiverPage({super.key});
  @override
  State<DecoderReceiverPage> createState() => _DecoderReceiverPageState();
}

class _DecoderReceiverPageState extends State<DecoderReceiverPage> {
  final m = DeeprowssMirrorService.instance;
  bool _busy = false;

  Future<void> _scanAndConnect() async {
    final pair = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(builder: (_) => const DecoderQrScanPage()),
    );
    if (!mounted || pair == null) return;
    setState(() => _busy = true);
    try {
      await m.start(captureScreen: false, relayRoom: pair['room'], relayToken: pair['token']);
      if (mounted) decoderToast(context, 'Paired with receiver. Choose a video or channel to send.');
    } catch (_) {
      if (mounted) decoderToast(context, m.error ?? 'Could not connect to receiver.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startLegacy() async {
    setState(() => _busy = true);
    try {
      await m.start(captureScreen: false);
      if (mounted) decoderToast(context, 'Manual receiver session started.');
    } catch (_) {
      if (mounted) decoderToast(context, m.error ?? 'Could not start receiver.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    appBar: AppBar(backgroundColor: Ui.panel,
      title: const Text('Connect to receiver', style: TextStyle(fontWeight: FontWeight.w900))),
    body: ListenableBuilder(listenable: m, builder: (context, _) => ListView(
      padding: const EdgeInsets.all(16), children: [
        decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.connected_tv_rounded, size: 29, color: Ui.red),
            const SizedBox(width: 11),
            Expanded(child: Text(m.running ? m.status : 'No receiver connected',
              style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900))),
            Icon(Icons.circle, size: 10, color: m.connected ? Colors.green : Ui.muted),
          ]),
          const SizedBox(height: 10),
          Text('On your TV or laptop, open the Deeprowss Receiver page. Scan the QR code shown there with your phone to connect.',
            style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.5)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _busy || m.running ? null : _scanAndConnect,
            icon: _busy ? const SizedBox(width: 17,height: 17,child:CircularProgressIndicator(strokeWidth:2))
              : const Icon(Icons.qr_code_scanner_rounded),
            label: Text(_busy ? 'Connecting…' : 'Scan TV QR code'))),
          if (!m.running) ...[
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _busy ? null : _startLegacy,
              icon: const Icon(Icons.pin_outlined), label: const Text('Use legacy PIN connection'))),
          ] else ...[
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () async { await m.stop(); },
              icon: const Icon(Icons.stop_circle_outlined), label: const Text('Disconnect receiver'))),
          ],
          if (m.error != null) Padding(padding: const EdgeInsets.only(top:10),
            child: Text(m.error!, style: TextStyle(color: Ui.red, fontSize:12))),
        ])),
        if (m.running && m.connected) decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.play_circle_fill,color:Ui.red),const SizedBox(width:8),
            Text('Now playing',style:TextStyle(color:Ui.text,fontWeight:FontWeight.w900,fontSize:17))]),
          const SizedBox(height:6),
          Text(m.nowPlayingTitle.isEmpty?'Waiting for media':m.nowPlayingTitle,maxLines:2,overflow:TextOverflow.ellipsis,
            style:TextStyle(color:Ui.text,fontWeight:FontWeight.w700)),
          const SizedBox(height:12),
          Row(children:[
            Expanded(child:_RemoteButton(icon:Icons.replay_10_rounded,label:'−10 sec',onTap:()=>m.sendRemoteCommand('rewind'))),
            const SizedBox(width:8),
            Expanded(child:_RemoteButton(icon:Icons.play_arrow_rounded,label:'Play',onTap:()=>m.sendRemoteCommand('play'),primary:true)),
            const SizedBox(width:8),
            Expanded(child:_RemoteButton(icon:Icons.pause_rounded,label:'Pause',onTap:()=>m.sendRemoteCommand('pause'))),
            const SizedBox(width:8),
            Expanded(child:_RemoteButton(icon:Icons.forward_10_rounded,label:'+10 sec',onTap:()=>m.sendRemoteCommand('forward'))),
          ]),
          const SizedBox(height:12),
          Row(children:[
            Expanded(child:OutlinedButton.icon(onPressed:()=>m.sendRemoteCommand('unmute'),
              icon:const Icon(Icons.volume_up_rounded,size:18),label:const FittedBox(child:Text('Unmute')))),
            const SizedBox(width:8),
            Expanded(child:OutlinedButton.icon(onPressed:()=>m.sendRemoteCommand('fullscreen'),
              icon:const Icon(Icons.fullscreen_rounded,size:18),label:const FittedBox(child:Text('Full screen')))),
            const SizedBox(width:8),
            Expanded(child:FilledButton.tonalIcon(onPressed:()=>m.stopPlayback(),
              icon:const Icon(Icons.stop_rounded,size:18),label:const FittedBox(child:Text('Stop')))),
          ]),
          Row(children:[
            const Icon(Icons.volume_down_rounded),
            Expanded(child:Slider(value:m.receiverVolume.toDouble(),min:0,max:100,onChanged:m.setReceiverVolume)),
            Text(m.receiverVolume.toString()+'%',style:TextStyle(color:Ui.muted,fontSize:11)),
          ]),
          Text('Direct streams support remote controls. Embedded providers may restrict external control.',
            style:TextStyle(color:Ui.muted,fontSize:11,height:1.35)),
        ])),
        decoderPanel(Text('The QR code pairs your phone with the TV. Video and audio travel directly between devices using WebRTC; the pairing service only relays connection messages.',
          style:TextStyle(color:Ui.muted,fontSize:12,height:1.5))),
      ])),
  );
}

class _RemoteButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _RemoteButton({required this.icon,required this.label,required this.onTap,this.primary=false});
  @override
  Widget build(BuildContext context)=>InkWell(onTap:onTap,borderRadius:BorderRadius.circular(14),
    child:Container(padding:const EdgeInsets.symmetric(horizontal:4,vertical:12),
      constraints:const BoxConstraints(minHeight:76),
      decoration:BoxDecoration(color:primary?Ui.red.withValues(alpha:.18):Ui.card,
        borderRadius:BorderRadius.circular(14),border:Border.all(color:primary?Ui.red:Ui.line)),
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        Icon(icon,color:primary?Ui.red:Ui.text,size:24),const SizedBox(height:5),
        FittedBox(fit:BoxFit.scaleDown,child:Text(label,maxLines:1,style:TextStyle(color:Ui.muted,fontSize:10))),
      ])));
}
