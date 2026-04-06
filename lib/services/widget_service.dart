import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../models/canvas_media.dart';
import '../models/stroke.dart';
import '../painters/canvas_painter.dart';

/// Pushes canvas state into the native Android home-screen widget.
class WidgetService {
  static const _androidWidgetName = 'SyncosisWidgetProvider';

  /// Renders the current strokes and media as a small PNG and updates the widget data.
  static Future<void> update({
    required List<Stroke> strokes,
    required List<CanvasMedia> mediaItems,
    String partnerName = 'Partner',
    String statusMessage = 'Scribbling together…',
  }) async {
    // 2. Render canvas preview as a 200x200 image
    try {
      final path = await _renderCanvasPreview(strokes, mediaItems);
      if (path != null) {
        await HomeWidget.saveWidgetData<String>('canvas_preview_path', path);
      }
    } catch (_) {
      // If rendering fails, the widget just won't show a preview — that's ok.
    }

    // 3. Trigger native widget refresh
    await HomeWidget.updateWidget(androidName: _androidWidgetName);
  }

  /// Renders the strokes and media to a PNG file and returns the path.
  static Future<String?> _renderCanvasPreview(
    List<Stroke> strokes,
    List<CanvasMedia> mediaItems,
  ) async {
    if (strokes.isEmpty && mediaItems.isEmpty) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 400, 400),
        Paint()..color = const Color(0xFFFDF8F3),
      );
      final picture = recorder.endRecording();
      final img = await picture.toImage(400, 400);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/widget_canvas_preview.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      return file.path;
    }

    // Find bounding box to zoom to content
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final stroke in strokes) {
      final halfW = stroke.width / 2;
      for (final pt in stroke.points) {
        if (pt.dx - halfW < minX) minX = pt.dx - halfW;
        if (pt.dy - halfW < minY) minY = pt.dy - halfW;
        if (pt.dx + halfW > maxX) maxX = pt.dx + halfW;
        if (pt.dy + halfW > maxY) maxY = pt.dy + halfW;
      }
    }

    final Map<String, ui.Image> loadedImages = {};

    for (final media in mediaItems) {
      final w = media.width;
      final h = media.height;
      final dx = media.position.dx;
      final dy = media.position.dy;

      // Simple bounding box approximation
      if (dx < minX) minX = dx;
      if (dy < minY) minY = dy;
      if (dx + w > maxX) maxX = dx + w;
      if (dy + h > maxY) maxY = dy + h;

      if (media.type == MediaType.image || media.type == MediaType.video) {
        try {
          Uint8List bytes;
          String targetUrl = media.url;
          if (media.type == MediaType.video) {
            final lastDot = targetUrl.lastIndexOf('.');
            if (lastDot != -1) {
              targetUrl = '${targetUrl.substring(0, lastDot)}.jpg';
            }
          }

          if (targetUrl.startsWith('http')) {
            final request = await HttpClient().getUrl(Uri.parse(targetUrl));
            final response = await request.close();
            bytes = await consolidateHttpClientResponseBytes(response);
          } else {
            bytes = await File(targetUrl).readAsBytes();
          }
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          loadedImages[media.id] = frame.image;

          if (media.metadata != null && media.metadata!['url2'] != null) {
            final url2 = media.metadata!['url2'] as String;
            Uint8List bytes2;
            if (url2.startsWith('http')) {
              final request2 = await HttpClient().getUrl(Uri.parse(url2));
              final response2 = await request2.close();
              bytes2 = await consolidateHttpClientResponseBytes(response2);
            } else {
              bytes2 = await File(url2).readAsBytes();
            }
            final codec2 = await ui.instantiateImageCodec(bytes2);
            final frame2 = await codec2.getNextFrame();
            loadedImages['${media.id}_2'] = frame2.image;
          }
        } catch (_) {
          // ignore image load errors
        }
      }
    }

    // Add padding to bounds so content isn't flush against the absolute edge of widget
    minX -= 40;
    minY -= 40;
    maxX += 40;
    maxY += 40;

    final contentW = (maxX - minX).clamp(1.0, double.infinity);
    final contentH = (maxY - minY).clamp(1.0, double.infinity);

    // Target a max dimension to avoid ultra high res memory issues
    final maxDim = contentW > contentH ? contentW : contentH;
    final scale = (600.0 / maxDim).clamp(
      0.1,
      2.0,
    ); // Allow scale up for single strokes

    final imgW = (contentW * scale).toInt().clamp(100, 1500);
    final imgH = (contentH * scale).toInt().clamp(100, 1500);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
      Paint()..color = const Color(0xFFFDF8F3), // Background
    );

    // Translate & scale so bonds fit exactly into image dimensions
    canvas.scale(scale);
    canvas.translate(-minX, -minY);

    // Draw media
    for (final media in mediaItems) {
      canvas.save();
      final w = media.width;
      final h = media.height;

      // Translate to CENTER of the media precisely so rotation pivots correctly!
      canvas.translate(media.position.dx + w / 2, media.position.dy + h / 2);
      canvas.rotate(media.rotation);

      final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);

      final meta = media.metadata;
      final isPost = meta != null && meta['isPost'] == true;

      if (isPost) {
        final isAudio = media.type == MediaType.audio;
        final title = meta['title'] as String?;
        final subtitle = meta['subtitle'] as String?;
        final quote = meta['quote'] as String?;
        final time = meta['timestamp'] as String?;
        final frame = meta['frame'] as String? ?? 'polaroid';
        final hasTwo = meta['url2'] != null;

        void drawSingleFrame(
          Rect renderRect,
          ui.Image? tImg,
          String? fTitle,
          String? fSub,
          String? fTime,
          double angle,
        ) {
          canvas.save();
          canvas.translate(renderRect.center.dx, renderRect.center.dy);
          canvas.rotate(angle);
          final localRect = Rect.fromCenter(
            center: Offset.zero,
            width: renderRect.width,
            height: renderRect.height,
          );
          final w = localRect.width;
          final h = localRect.height;

          if (frame == 'film' && !isAudio) {
            final rRect = RRect.fromRectAndRadius(
              localRect,
              const Radius.circular(4),
            );
            canvas.drawShadow(
              Path()..addRRect(rRect),
              const Color(0x88000000),
              16,
              true,
            );
            canvas.drawRRect(rRect, Paint()..color = const Color(0xFF111113));

            // draw left & right sprockets
            final spSpacing = h / 11;
            for (var i = 1; i <= 10; i++) {
              final spY = -h / 2 + (i * spSpacing) - 6;
              final r1 = RRect.fromRectAndRadius(
                Rect.fromLTWH(-w / 2 + 8, spY, 8, 12),
                const Radius.circular(2),
              );
              final r2 = RRect.fromRectAndRadius(
                Rect.fromLTWH(w / 2 - 16, spY, 8, 12),
                const Radius.circular(2),
              );
              canvas.drawRRect(
                r1,
                Paint()..color = const Color(0xFFFDFBF7),
              ); // Canvas background color assumption
              canvas.drawRRect(r2, Paint()..color = const Color(0xFFFDFBF7));
            }

            final fTitleH = (fTitle != null && fTitle.isNotEmpty) ? 28 : 0;
            final subH = (fSub != null && fSub.isNotEmpty || fTime != null)
                ? 14
                : 0;
            final textSpace = (fTitleH > 0 || subH > 0)
                ? (fTitleH + subH + 16)
                : 0;

            final imgRect = Rect.fromLTRB(
              -w / 2 + 24,
              -h / 2 + 16,
              w / 2 - 24,
              h / 2 - 16 - textSpace,
            );

            if (media.type == MediaType.image ||
                media.type == MediaType.video) {
              final img = tImg;
              if (img != null) {
                final innerRRect = RRect.fromRectAndRadius(
                  imgRect,
                  const Radius.circular(2),
                );
                canvas.save();
                canvas.clipRRect(innerRRect);

                double imgAR = img.width / img.height;
                double dstAR = imgRect.width / imgRect.height;
                Rect src;
                if (imgAR > dstAR) {
                  double cropW = img.height * dstAR;
                  double offset = (img.width - cropW) / 2;
                  src = Rect.fromLTWH(offset, 0, cropW, img.height.toDouble());
                } else {
                  double cropH = img.width / dstAR;
                  double offset = (img.height - cropH) / 2;
                  src = Rect.fromLTWH(0, offset, img.width.toDouble(), cropH);
                }

                canvas.drawImageRect(
                  img,
                  src,
                  imgRect,
                  Paint()..filterQuality = FilterQuality.high,
                );
                if (media.type == MediaType.video) {
                  canvas.drawRect(
                    imgRect,
                    Paint()..color = const Color(0x66000000),
                  );
                  canvas.drawCircle(
                    imgRect.center,
                    24,
                    Paint()..color = const Color(0xCC000000),
                  );
                  final playPath = Path()
                    ..moveTo(imgRect.center.dx - 8, imgRect.center.dy - 12)
                    ..lineTo(imgRect.center.dx + 12, imgRect.center.dy)
                    ..lineTo(imgRect.center.dx - 8, imgRect.center.dy + 12)
                    ..close();
                  canvas.drawPath(playPath, Paint()..color = Colors.white);
                }
                canvas.restore();
              } else {
                canvas.drawRect(
                  imgRect,
                  Paint()..color = const Color(0xFF333333),
                );
              }
            }

            // Draw text
            if (fTitle != null && fTitle.isNotEmpty) {
              final tp = TextPainter(
                text: TextSpan(
                  text: fTitle,
                  style: GoogleFonts.inriaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                textDirection: TextDirection.ltr,
              );
              tp.layout(maxWidth: w - 48);
              tp.paint(canvas, Offset(-w / 2 + 28, h / 2 - textSpace + 6));
            }

            if (fSub != null || fTime != null) {
              if (fSub != null && fSub.isNotEmpty) {
                final tpSub = TextPainter(
                  text: TextSpan(
                    text: fSub.toUpperCase(),
                    style: GoogleFonts.inriaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.white54,
                    ),
                  ),
                  textDirection: TextDirection.ltr,
                );
                tpSub.layout();
                tpSub.paint(canvas, Offset(-w / 2 + 28, h / 2 - 20));
              }
              if (fTime != null) {
                final tpTime = TextPainter(
                  text: TextSpan(
                    text: fTime,
                    style: GoogleFonts.inriaSans(
                      fontSize: 10,
                      color: Colors.white54,
                    ),
                  ),
                  textDirection: TextDirection.ltr,
                );
                tpTime.layout();
                tpTime.paint(
                  canvas,
                  Offset(w / 2 - 28 - tpTime.width, h / 2 - 20),
                );
              }
            }
          } else {
            // Standard polaroid background
            final rRect = RRect.fromRectAndRadius(
              localRect,
              Radius.circular(isAudio ? 28 : 12),
            );
            canvas.drawShadow(
              Path()..addRRect(rRect),
              const Color(0x44000000),
              12,
              true,
            );
            canvas.drawRRect(rRect, Paint()..color = Colors.white);

            if (!isAudio) {
              final imgH = h - 64;
              final imgRect = Rect.fromLTRB(
                -w / 2 + 10,
                -h / 2 + 10,
                w / 2 - 10,
                -h / 2 + imgH,
              );

              if (media.type == MediaType.image ||
                  media.type == MediaType.video) {
                final img = tImg;
                if (img != null) {
                  final innerRRect = RRect.fromRectAndRadius(
                    imgRect,
                    const Radius.circular(4),
                  );
                  canvas.save();
                  canvas.clipRRect(innerRRect);

                  double imgAR = img.width / img.height;
                  double dstAR = imgRect.width / imgRect.height;
                  Rect src;
                  if (imgAR > dstAR) {
                    double cropW = img.height * dstAR;
                    double offset = (img.width - cropW) / 2;
                    src = Rect.fromLTWH(
                      offset,
                      0,
                      cropW,
                      img.height.toDouble(),
                    );
                  } else {
                    double cropH = img.width / dstAR;
                    double offset = (img.height - cropH) / 2;
                    src = Rect.fromLTWH(0, offset, img.width.toDouble(), cropH);
                  }

                  canvas.drawImageRect(
                    img,
                    src,
                    imgRect,
                    Paint()..filterQuality = FilterQuality.high,
                  );
                  if (media.type == MediaType.video) {
                    canvas.drawRect(
                      imgRect,
                      Paint()..color = const Color(0x66000000),
                    );
                    canvas.drawCircle(
                      imgRect.center,
                      24,
                      Paint()..color = const Color(0xCC000000),
                    );
                    final playPath = Path()
                      ..moveTo(imgRect.center.dx - 8, imgRect.center.dy - 12)
                      ..lineTo(imgRect.center.dx + 12, imgRect.center.dy)
                      ..lineTo(imgRect.center.dx - 8, imgRect.center.dy + 12)
                      ..close();
                    canvas.drawPath(playPath, Paint()..color = Colors.white);
                  }
                  canvas.restore();
                } else {
                  canvas.drawRect(
                    imgRect,
                    Paint()..color = const Color(0xFFDDDDDD),
                  );
                }
              }

              if (fTitle != null && fTitle.isNotEmpty) {
                final tp = TextPainter(
                  text: TextSpan(
                    text: fTitle,
                    style: GoogleFonts.inriaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2D1B3D),
                    ),
                  ),
                  textDirection: TextDirection.ltr,
                );
                tp.layout(maxWidth: w - 20);
                tp.paint(canvas, Offset(-w / 2 + 14, h / 2 - 44));
              }

              if (fSub != null || fTime != null) {
                if (fSub != null && fSub.isNotEmpty) {
                  final tpSub = TextPainter(
                    text: TextSpan(
                      text: fSub.toUpperCase(),
                      style: GoogleFonts.inriaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: const Color(0xFF9E9E9E),
                      ),
                    ),
                    textDirection: TextDirection.ltr,
                  );
                  tpSub.layout();
                  tpSub.paint(canvas, Offset(-w / 2 + 14, h / 2 - 22));
                }
                if (fTime != null) {
                  final tpTime = TextPainter(
                    text: TextSpan(
                      text: fTime,
                      style: GoogleFonts.inriaSans(
                        fontSize: 10,
                        color: const Color(0xFF9E9E9E),
                      ),
                    ),
                    textDirection: TextDirection.ltr,
                  );
                  tpTime.layout();
                  tpTime.paint(
                    canvas,
                    Offset(w / 2 - 14 - tpTime.width, h / 2 - 22),
                  );
                }
              }

              // Draw decorative tape
              canvas.save();
              canvas.translate(w / 2 - 40, -h / 2 + 3);
              canvas.rotate(-0.15);
              canvas.drawRect(
                const Rect.fromLTWH(0, 1, 44, 14),
                Paint()..color = Colors.black.withOpacity(0.1),
              ); // shadow
              canvas.drawRect(
                const Rect.fromLTWH(0, 0, 44, 14),
                Paint()..color = const Color(0xFFDAA045).withOpacity(0.95),
              ); // tape
              canvas.restore();
            } else {
              // Draw top Play button and progress bar
              canvas.drawCircle(
                Offset(-w / 2 + 40, -h / 2 + 40),
                24,
                Paint()..color = const Color(0xFFD34F73),
              );
              final playPath = Path()
                ..moveTo(-w / 2 + 40 - 6, -h / 2 + 40 - 10)
                ..lineTo(-w / 2 + 40 + 10, -h / 2 + 40)
                ..lineTo(-w / 2 + 40 - 6, -h / 2 + 40 + 10)
                ..close();
              canvas.drawPath(playPath, Paint()..color = Colors.white);

              // Draw progress bar
              final trackRect = Rect.fromLTRB(
                -w / 2 + 78,
                -h / 2 + 38,
                w / 2 - 16,
                -h / 2 + 42,
              );
              canvas.drawRRect(
                RRect.fromRectAndRadius(trackRect, const Radius.circular(2)),
                Paint()..color = const Color(0xFFF1EBE3),
              );
              final progressRect = Rect.fromLTRB(
                -w / 2 + 78,
                -h / 2 + 38,
                -w / 2 + 120,
                -h / 2 + 42,
              ); // Static visual progress
              canvas.drawRRect(
                RRect.fromRectAndRadius(progressRect, const Radius.circular(2)),
                Paint()..color = const Color(0xFFA12C4D),
              );

              final tpDur1 = TextPainter(
                text: TextSpan(
                  text: '0:00',
                  style: GoogleFonts.inriaSans(
                    fontSize: 10,
                    color: const Color(0xFF8F8A83),
                  ),
                ),
                textDirection: TextDirection.ltr,
              )..layout();
              tpDur1.paint(canvas, Offset(-w / 2 + 78, -h / 2 + 46));
              final tpDur2 = TextPainter(
                text: TextSpan(
                  text: '0:30',
                  style: GoogleFonts.inriaSans(
                    fontSize: 10,
                    color: const Color(0xFF8F8A83),
                  ),
                ),
                textDirection: TextDirection.ltr,
              )..layout();
              tpDur2.paint(
                canvas,
                Offset(w / 2 - 16 - tpDur2.width, -h / 2 + 46),
              );

              double currentY = -h / 2 + 76;

              if (quote != null && quote.isNotEmpty) {
                final quoteRect = Rect.fromLTRB(
                  -w / 2 + 16,
                  currentY,
                  w / 2 - 16,
                  h / 2 - 36,
                );
                final quoteRRect = RRect.fromRectAndCorners(
                  quoteRect,
                  topLeft: const Radius.circular(24),
                  topRight: const Radius.circular(24),
                  bottomLeft: const Radius.circular(24),
                  bottomRight: const Radius.circular(4),
                );

                // Clip internal quote bubble
                canvas.save();
                canvas.clipRRect(quoteRRect);
                canvas.drawRRect(
                  quoteRRect,
                  Paint()
                    ..color = const Color(0xFFFBF7F1)
                    ..style = PaintingStyle.fill,
                );
                // Left gold line
                canvas.drawRect(
                  Rect.fromLTRB(-w / 2 + 16, currentY, -w / 2 + 20, h / 2 - 36),
                  Paint()..color = const Color(0xFFB18941),
                );
                canvas.restore();

                final tpQ = TextPainter(
                  text: TextSpan(
                    text: '"$quote"',
                    style: GoogleFonts.lora(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: const Color(0xFF7A6034),
                    ),
                  ),
                  textDirection: TextDirection.ltr,
                  maxLines: 3,
                );
                tpQ.layout(maxWidth: w - 52);
                tpQ.paint(canvas, Offset(-w / 2 + 32, currentY + 14));
              }

              // VOICE NOTE + Time
              final tpVoice = TextPainter(
                text: TextSpan(
                  text: 'VOICE NOTE',
                  style: GoogleFonts.inriaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: const Color(0xFF9E9E9E),
                  ),
                ),
                textDirection: TextDirection.ltr,
              )..layout();
              tpVoice.paint(canvas, Offset(-w / 2 + 32, h / 2 - 24));

              // Native UI Mic Icon representation
              final micRect = Rect.fromCenter(
                center: Offset(-w / 2 + 22, h / 2 - 19),
                width: 4,
                height: 8,
              );
              canvas.drawRRect(
                RRect.fromRectAndRadius(micRect, const Radius.circular(4)),
                Paint()..color = const Color(0xFF9E9E9E),
              );
              canvas.drawArc(
                Rect.fromCenter(
                  center: Offset(-w / 2 + 22, h / 2 - 19),
                  width: 8,
                  height: 8,
                ),
                0,
                3.14,
                false,
                Paint()
                  ..color = const Color(0xFF9E9E9E)
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.5,
              );
              canvas.drawLine(
                Offset(-w / 2 + 22, h / 2 - 15),
                Offset(-w / 2 + 22, h / 2 - 13),
                Paint()
                  ..color = const Color(0xFF9E9E9E)
                  ..strokeWidth = 1.5,
              );
              canvas.drawLine(
                Offset(-w / 2 + 19, h / 2 - 13),
                Offset(-w / 2 + 25, h / 2 - 13),
                Paint()
                  ..color = const Color(0xFF9E9E9E)
                  ..strokeWidth = 1.5,
              );

              if (fTime != null) {
                final tpTime = TextPainter(
                  text: TextSpan(
                    text: fTime,
                    style: GoogleFonts.inriaSans(
                      fontSize: 10,
                      color: const Color(0xFF9E9E9E),
                    ),
                  ),
                  textDirection: TextDirection.ltr,
                )..layout();
                tpTime.paint(
                  canvas,
                  Offset(w / 2 - 16 - tpTime.width, h / 2 - 24),
                );
              }
            }
          }

          canvas.restore();
        }

        if (hasTwo && !isAudio) {
          final rect1 = Rect.fromLTWH(
            rect.left + rect.width * 0.30,
            rect.top,
            rect.width * 0.70,
            rect.height * 0.70,
          );
          drawSingleFrame(
            rect1,
            loadedImages[media.id],
            null,
            null,
            time,
            0.1,
          );

          final rect2 = Rect.fromLTWH(
            rect.left,
            rect.bottom - rect.height * 0.70,
            rect.width * 0.70,
            rect.height * 0.70,
          );
          drawSingleFrame(
            rect2,
            loadedImages['${media.id}_2'],
            null,
            null,
            null,
            -0.1,
          );
        } else {
          drawSingleFrame(
            rect,
            loadedImages[media.id],
            title,
            subtitle,
            time,
            0,
          );
        }
      } else {
        if (media.type == MediaType.image || media.type == MediaType.video) {
          final img = loadedImages[media.id];
          if (img != null) {
            canvas.drawImageRect(
              img,
              Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
              rect,
              Paint()..filterQuality = FilterQuality.high,
            );
            if (media.type == MediaType.video) {
              canvas.drawRect(rect, Paint()..color = const Color(0x66000000));
              canvas.drawCircle(
                Offset.zero,
                30,
                Paint()..color = const Color(0xCC000000),
              );
              final playPath = Path()
                ..moveTo(-10, -15)
                ..lineTo(15, 0)
                ..lineTo(-10, 15)
                ..close();
              canvas.drawPath(playPath, Paint()..color = Colors.white);
            }
          } else {
            canvas.drawRect(rect, Paint()..color = const Color(0xFFDDDDDD));
          }
        } else if (media.type == MediaType.text) {
          int colorInt = 0xFF2D1B3D;
          try {
            colorInt = int.parse(media.filename, radix: 16);
          } catch (_) {}
          final textPainter = TextPainter(
            text: TextSpan(
              text: media.url,
              style: GoogleFonts.lora(
                fontWeight: FontWeight.w600,
                color: Color(colorInt),
                fontSize: h * 0.8,
              ),
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
          );
          textPainter.layout(maxWidth: double.infinity);
          textPainter.paint(
            canvas,
            Offset(-textPainter.width / 2, -textPainter.height / 2),
          );
        } else if (media.type == MediaType.audio) {
          final rrect = RRect.fromRectAndRadius(
            rect,
            const Radius.circular(50),
          );
          canvas.drawShadow(
            Path()..addRRect(rrect),
            const Color(0x66000000),
            4,
            true,
          );
          canvas.drawRRect(rrect, Paint()..color = const Color(0xFFFFFFFF));
          canvas.drawCircle(
            Offset(-w / 2 + h / 2, 0),
            h / 2 - 10,
            Paint()..color = const Color(0xFFD34F73),
          );
          final path = Path()
            ..moveTo(-w / 2 + h / 2 - 4, -6)
            ..lineTo(-w / 2 + h / 2 + 6, 0)
            ..lineTo(-w / 2 + h / 2 - 4, 6)
            ..close();
          canvas.drawPath(path, Paint()..color = const Color(0xFFFFFFFF));
          final tp = TextPainter(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Voice note\n',
                  style: GoogleFonts.inriaSans(
                    color: const Color(0xFF2D1B3D),
                    fontWeight: FontWeight.bold,
                    fontSize: h * 0.35,
                  ),
                ),
                TextSpan(
                  text: 'Tap to play',
                  style: GoogleFonts.inriaSans(
                    color: const Color(0xFF9E9E9E),
                    fontSize: h * 0.25,
                  ),
                ),
              ],
            ),
            textDirection: TextDirection.ltr,
          );
          tp.layout();
          tp.paint(canvas, Offset(-w / 2 + h + 10, -tp.height / 2));
        }
      }

      canvas.restore();
    }

    // Draw strokes
    final painter = CanvasPainter(strokes: strokes, partnerCursor: null);
    painter.paint(canvas, const Size(10000, 10000));

    final picture = recorder.endRecording();
    final img = await picture.toImage(imgW, imgH);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/widget_canvas_preview.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());

    return file.path;
  }
}
