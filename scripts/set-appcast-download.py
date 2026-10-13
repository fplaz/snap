"""Set one build's immutable download URL before re-signing its appcast."""

import sys
from pathlib import Path
from urllib.parse import urlsplit
from xml.dom import minidom

SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def set_download(feed: Path, build: str, url: str) -> None:
    parsed = urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or "/releases/latest/" in parsed.path:
        raise ValueError("Use an HTTPS URL for a specific release.")
    document = minidom.parse(str(feed))
    matches = []
    for item in document.getElementsByTagName("item"):
        versions = [node for node in item.childNodes
                    if node.namespaceURI == SPARKLE_NAMESPACE and node.localName == "version"]
        if len(versions) == 1 and versions[0].firstChild and versions[0].firstChild.nodeValue == build:
            enclosures = [node for node in item.childNodes if node.nodeName == "enclosure"]
            if len(enclosures) != 1:
                raise ValueError("Expected one download enclosure for the release build.")
            matches.append(enclosures[0])
    if len(matches) != 1:
        raise ValueError("Expected exactly one appcast item for the release build.")
    matches[0].setAttribute("url", url)
    # Keep embedded HTML release notes as CDATA. sign_update replaces the old signature.
    feed.write_bytes(document.toxml(encoding="utf-8"))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("Usage: set-appcast-download.py APPCAST BUILD HTTPS_RELEASE_URL")
    try:
        set_download(Path(sys.argv[1]), sys.argv[2], sys.argv[3])
    except ValueError as error:
        sys.exit(str(error))
