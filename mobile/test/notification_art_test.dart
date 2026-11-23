import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/playback/data/notification_art.dart';

void main() {
  test('las portadas de Google se piden cuadradas y grandes', () {
    final art = NotificationArt.immediate(
      'https://lh3.googleusercontent.com/abc=w120-h120-l90-rj',
    );
    expect(
      art.toString(),
      'https://lh3.googleusercontent.com/abc=w544-h544-l90-rj',
    );
  });

  test('una miniatura de vídeo espera a su portada recortada', () {
    expect(
      NotificationArt.immediate(
        'https://i.ytimg.com/vi/ABCDEFGHIJK/default.jpg',
      ),
      isNull,
    );
    expect(
      NotificationArt.immediate(
        'https://i.ytimg.com/vi/ABCDEFGHIJK/hqdefault.jpg',
      ),
      isNull,
    );
  });

  test('otras imágenes y la ausencia de portada se respetan', () {
    expect(NotificationArt.immediate(null), isNull);
    expect(
      NotificationArt.immediate('https://example.test/cover.png').toString(),
      'https://example.test/cover.png',
    );
  });
}
