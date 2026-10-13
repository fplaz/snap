import importlib.util
import tempfile
import unittest
from pathlib import Path
from xml.dom import minidom

SPEC = importlib.util.spec_from_file_location("set_download", Path(__file__).parents[1] / "set-appcast-download.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

FEED = '''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<item><sparkle:version>10</sparkle:version><enclosure url="https://example.com/v1.2/Snap-1.2.dmg" length="100" sparkle:edSignature="old-signature"/></item>
<item><sparkle:version>11</sparkle:version><description><![CDATA[<ul><li>Update</li></ul>]]></description><enclosure url="https://example.com/v1.3/Snap-1.3.dmg" length="200" sparkle:edSignature="new-signature"/></item>
</channel></rss>'''


class DownloadURLTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.feed = Path(self.directory.name) / "appcast.xml"
        self.feed.write_text(FEED)

    def test_changes_only_selected_release_and_preserves_archive_metadata_and_notes(self):
        MODULE.set_download(self.feed, "11", "https://example.com/v1.3/Snap.dmg")
        document = minidom.parse(str(self.feed))
        old, current = document.getElementsByTagName("enclosure")
        self.assertEqual(old.getAttribute("url"), "https://example.com/v1.2/Snap-1.2.dmg")
        self.assertEqual(old.getAttribute("sparkle:edSignature"), "old-signature")
        self.assertEqual(current.getAttribute("url"), "https://example.com/v1.3/Snap.dmg")
        self.assertEqual(current.getAttribute("length"), "200")
        self.assertEqual(current.getAttribute("sparkle:edSignature"), "new-signature")
        description = document.getElementsByTagName("description")[0].firstChild
        self.assertEqual(description.nodeType, description.CDATA_SECTION_NODE)
        self.assertEqual(description.nodeValue, "<ul><li>Update</li></ul>")

    def test_rejects_mutable_latest_url_and_http_without_changing_feed(self):
        for url in ("https://github.com/fplaz/snap/releases/latest/download/Snap.dmg", "http://example.com/v1.3/Snap.dmg"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                MODULE.set_download(self.feed, "11", url)
            self.assertEqual(self.feed.read_text(), FEED)

    def test_rejects_missing_or_duplicate_build_without_changing_feed(self):
        for contents, build in ((FEED, "12"), (FEED.replace("<sparkle:version>10</sparkle:version>", "<sparkle:version>11</sparkle:version>"), "11")):
            self.feed.write_text(contents)
            with self.subTest(build=build), self.assertRaises(ValueError):
                MODULE.set_download(self.feed, build, "https://example.com/v1.3/Snap.dmg")
            self.assertEqual(self.feed.read_text(), contents)


if __name__ == "__main__":
    unittest.main()
