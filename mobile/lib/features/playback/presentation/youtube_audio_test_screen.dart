import '../../search/domain/catalog_track.dart';
import 'package:flutter/material.dart';
import 'playback_availability_panel.dart';

class YoutubeAudioTestScreen extends StatelessWidget {
  const YoutubeAudioTestScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Audio de YouTube')),
    body: const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Big Buck Bunny', style: TextStyle(fontSize: 24)),
            SizedBox(height: 12),
            Text(
              'Fuente de prueba abierta de YouTube. Escucharás su pista de audio, sin vídeo.',
            ),
            SizedBox(height: 16),
            PlaybackAvailabilityPanel(
              track: CatalogTrack(
                id: 'youtube:aqz-KE-bpKQ',
                title: 'Big Buck Bunny',
                artistName: 'Blender Foundation',
              ),
            ),
            SizedBox(height: 16),
            Text(
              '© 2008 Blender Foundation · bigbuckbunny.org · CC BY 3.0 · https://peach.blender.org/about/',
            ),
          ],
        ),
      ),
    ),
  );
}
