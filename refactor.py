import re
import sys

def refactor_canvas():
    path = 'lib/screens/canvas_screen.dart'
    with open(path, 'r', encoding='utf-8') as f:
        code = f.read()
    
    # Target replacement for `_buildMediaContent`
    pattern = r"""(    if \(item\.metadata != null && item\.metadata!\['isPost'\] == true\) \{
      final isAudio = item\.type == MediaType\.audio;
      final m = item\.metadata!;
      final title = m\['title'\] as String\?;
      final subtitle = m\['subtitle'\] as String\?;
      final quote = m\['quote'\] as String\?;
      final time = m\['timestamp'\] as String\?;
)(      return Stack\(.*?          \),
          if \(!isAudio\)
            Positioned\(
              top: -4,
              right: 18,
              child: Transform\.rotate\(.*?              \),
            \),
        \],
      \);
    \})"""

    match = re.search(pattern, code, re.DOTALL)
    if not match:
        print("Failed to find canvas_screen Post block")
        return
    
    pre = match.group(1)
    original_stack = match.group(2)
    # The original_stack ends with `});`, so drop the `\n    }`
    original_stack = original_stack[:-5]
    
    # Inject our new logic
    replacement = pre + """      final frame = m['frame'] as String? ?? 'polaroid';
      final String? url2 = m['url2'] as String?;
      final bool hasTwo = url2 != null;

      Widget buildSingleFrame(String targetUrl, String? fTitle, String? fSubtitle, String? fTime, bool isSecondary) {
        final tMediaWidget = isSecondary ? Image.network(
          targetUrl,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorBuilder: (_, __, ___) => Container(color: Colors.grey[200]),
        ) : mediaWidget;

        if (frame == 'film' && !isAudio) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111113),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 24,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    10,
                    (_) => Container(
                      width: 8,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F7F4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: tMediaWidget,
                      ),
                    ),
                    if ((fTitle != null && fTitle.isNotEmpty) || (fSubtitle != null && fSubtitle.isNotEmpty) || (fTime != null))
                      Padding(
                        padding: const EdgeInsets.only(top: 12, left: 4, right: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (fTitle != null && fTitle.isNotEmpty)
                              Text(
                                fTitle,
                                style: GoogleFonts.inriaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (fTitle != null && fTitle.isNotEmpty)
                              const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (fSubtitle != null && fSubtitle.isNotEmpty)
                                  Expanded(
                                    child: Text(
                                      fSubtitle.toUpperCase(),
                                      style: GoogleFonts.inriaSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.2,
                                        color: Colors.white54,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                if (fTime != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: Text(
                                      fTime,
                                      style: GoogleFonts.inriaSans(
                                        fontSize: 10,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 24,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    10,
                    (_) => Container(
                      width: 8,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F7F4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }

""" + original_stack.replace("mediaWidget,", "tMediaWidget,").replace("mediaWidget", "tMediaWidget").replace("title,", "fTitle,").replace("title", "fTitle").replace("subtitle.", "fSubtitle.").replace("(subtitle", "(fSubtitle").replace("subtitle", "fSubtitle").replace("time,", "fTime,").replace("time", "fTime") + """
      }

      if (hasTwo && !isAudio) {
         return SizedBox(
           width: item.width,
           height: item.height,
           child: Stack(
             clipBehavior: Clip.none,
             children: [
               Positioned(
                 top: 0,
                 right: 0,
                 width: item.width * 0.70,
                 height: item.height * 0.70,
                 child: Transform.rotate(
                   angle: 0.1,
                   child: buildSingleFrame(item.url, title, subtitle, time, false),
                 ),
               ),
               Positioned(
                 bottom: 0,
                 left: 0,
                 width: item.width * 0.70,
                 height: item.height * 0.70,
                 child: Transform.rotate(
                   angle: -0.1,
                   child: buildSingleFrame(url2, null, null, null, true),
                 ),
               ),
             ]
           )
         );
      }

      return buildSingleFrame(item.url, title, subtitle, time, false);
    }"""
    
    new_code = code[:match.start()] + replacement + code[match.end():]
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_code)
    print("canvas_screen.dart refactor executed")

def refactor_widget_service():
    path = 'lib/services/widget_service.dart'
    with open(path, 'r', encoding='utf-8') as f:
        code = f.read()

    # Pre-load URL2
    pattern_url1 = r"""          if \(targetUrl\.startsWith\('http'\)\) \{
            final request = await HttpClient\(\)\.getUrl\(Uri\.parse\(targetUrl\)\);
            final response = await request\.close\(\);
            bytes = await consolidateHttpClientResponseBytes\(response\);
          \} else \{
            bytes = await File\(targetUrl\)\.readAsBytes\(\);
          \}
          final codec = await ui\.instantiateImageCodec\(bytes\);
          final frame = await codec\.getNextFrame\(\);
          loadedImages\[media.id\] = frame\.image;"""
    
    match_url1 = re.search(pattern_url1, code)
    if not match_url1:
        print("Failed to find WidgetService loadImages URL1")
        return
    
    replacement_url1 = match_url1.group(0) + """

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
          }"""
    
    code = code[:match_url1.start()] + replacement_url1 + code[match_url1.end():]

    
    pattern_draw = r"""(      if \(isPost\) \{
        final isAudio = media\.type == MediaType\.audio;
        final title = meta\['title'\] as String\?;
        final subtitle = meta\['subtitle'\] as String\?;
        final quote = meta\['quote'\] as String\?;
        final time = meta\['timestamp'\] as String\?;
        final frame = meta\['frame'\] as String\? \?\? 'polaroid';)(.*?)      \} else \{
        if \(media\.type == MediaType\.image \|\| media\.type == MediaType\.video\) \{"""

    match_draw = re.search(pattern_draw, code, re.DOTALL)
    if not match_draw:
        print("Failed to find WidgetService draw block")
        return
        
    pre = match_draw.group(1)
    original_draw = match_draw.group(2)
    # the original_draw has the logic for checking `frame == 'film'` etc.
    # we want to abstract this into `void drawSingleFrame(Rect renderRect, ui.Image? tImg, String? fTitle, String? fSub, String? fTime, double angle)` 
    
    new_draw = pre + """
        final hasTwo = meta['url2'] != null;

        void drawSingleFrame(Rect renderRect, ui.Image? tImg, String? fTitle, String? fSub, String? fTime, double angle) {
            canvas.save();
            canvas.translate(renderRect.center.dx, renderRect.center.dy);
            canvas.rotate(angle);
            final localRect = Rect.fromCenter(center: Offset.zero, width: renderRect.width, height: renderRect.height);
            final w = localRect.width;
            final h = localRect.height;
""" + original_draw.replace("loadedImages[media.id]", "tImg").replace("rect,", "localRect,").replace("rect", "localRect").replace("title,", "fTitle,").replace("title", "fTitle").replace("subtitle.", "fSub.").replace("(subtitle ", "(fSub ").replace("subtitle", "fSub").replace("time,", "fTime,").replace("time", "fTime") + """
            canvas.restore();
        }

        if (hasTwo && !isAudio) {
            final rect1 = Rect.fromLTWH(rect.left + rect.width*0.30, rect.top, rect.width * 0.70, rect.height * 0.70);
            drawSingleFrame(rect1, loadedImages[media.id], title, subtitle, time, 0.1);

            final rect2 = Rect.fromLTWH(rect.left, rect.bottom - rect.height*0.70, rect.width * 0.70, rect.height * 0.70);
            drawSingleFrame(rect2, loadedImages['${media.id}_2'], null, null, null, -0.1);
        } else {
            drawSingleFrame(rect, loadedImages[media.id], title, subtitle, time, 0);
        }
"""
    
    new_code = code[:match_draw.start()] + new_draw + code[match_draw.end() - len("      } else {\n        if (media.type == MediaType.image || media.type == MediaType.video) {"):]
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_code)
    print("widget_service.dart refactor executed")

if __name__ == '__main__':
    refactor_canvas()
    refactor_widget_service()
