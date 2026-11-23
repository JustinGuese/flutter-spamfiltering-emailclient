import 'package:data_fortress_mail/mail/html_to_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strips tags, keeps paragraphs, decodes entities', () {
    final t = htmlToText('<html><head><style>p{color:red}</style></head><body>'
        '<p>Hello&nbsp;&amp; welcome</p><p>Line<br>two &#8212; &#x41;</p>'
        '<ul><li>one</li><li>two</li></ul><script>alert(1)</script></body></html>');
    expect(t, 'Hello & welcome\n\nLine\ntwo — A\n\n• one\n• two');
  });

  test('empty for markup-only html', () {
    expect(htmlToText('<div> <img src="x"> </div>'), '');
  });
}
