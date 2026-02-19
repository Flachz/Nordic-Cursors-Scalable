#!/usr/bin/env bash
#
# Build script to build Nordic Cursors Scalable Theme

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit
THREADS="${THREADS:=$(nproc)}"
RAWSVG="src/cursors.svg"
INDEX="src/index.theme"
ALIASES="src/cursorList"
METADATA="src/metadata"
SVGS="src/svg"


echo -ne "Checking Requirements...\\r"
if [ ! -f $RAWSVG ]; then
	echo -e "\\nFAIL: '$RAWSVG' missing in /src"
	exit 1
fi

if [ ! -f $INDEX ]; then
	echo -e "\\nFAIL: '$INDEX' missing in /src"
	exit 1
fi

if  ! type "inkscape" > /dev/null; then
	echo -e "\\nFAIL: inkscape must be installed"
	exit 1
fi

if  ! type "xcursorgen" > /dev/null; then
	echo -e "\\nFAIL: xcursorgen must be installed"
	exit 1
fi
echo "Checking Requirements... DONE"



echo -ne "Making Folders...\\r"
RESOLUTIONS="$(seq -s ' ' 12 2 46) $(seq -s ' ' 48 6 72) $(seq -s ' ' 80 8 96)"
PIXMAPS="build/pixmaps"
OUTPUT="build/$(grep -oP "(?<=Name\=).*$" "$INDEX" | tr '[:upper:] ' '[:lower:]_')"

mkdir -p "$OUTPUT/cursors"
mkdir -p "$OUTPUT/cursors_scalable"

for RES in $RESOLUTIONS; do
	mkdir -p "$PIXMAPS/${RES}px"
done

for JSON in "$METADATA/"*.json; do
	BASENAME="${JSON##*/}"
	BASENAME="${BASENAME%.*}"
	mkdir -p "$OUTPUT/cursors_scalable/$BASENAME"
done

echo 'Making Folders... DONE';



for CUR in src/config/*.cursor; do
	BASENAME="${CUR##*/}"
	BASENAME="${BASENAME%.*}"

	echo -ne "\033[0KGenerating simple cursor pixmaps... $BASENAME\\r"

	for RES in $RESOLUTIONS; do
		DPI=$((RES * 4))
		[ "$(jobs -rp | wc -l)" -ge "$THREADS" ] && wait -n
		[ "$PIXMAPS/${RES}px/$BASENAME.png" -ot $RAWSVG ] && \
		unshare -U inkscape -i "$BASENAME" -d "$DPI" "$RAWSVG" \
			--export-background-opacity=0  \
			--export-filename="$PIXMAPS/${RES}px/$BASENAME.png" \
			>/dev/null 2>&1 &
	done
	wait
done
echo -e "\033[0KGenerating simple cursor pixmaps... DONE"



for i in $(seq -w 1 23); do
	echo -ne "\033[0KGenerating animated cursor pixmaps... $i / 23 \\r"

	for RES in $RESOLUTIONS; do
		DPI=$((RES * 4))
		for ANI in progress wait; do
			[ "$(jobs -rp | wc -l)" -ge "$THREADS" ] && wait -n
			[ "$PIXMAPS/${RES}px/$ANI-$i.png" -ot $RAWSVG ] && \
			unshare -U inkscape -i "$ANI-$i" -d "$DPI" "$RAWSVG" \
				--export-background-opacity=0  \
				--export-filename="$PIXMAPS/${RES}px/$ANI-$i.png" \
				>/dev/null 2>&1 &
		done
	done
	wait
done
echo -e "\033[0KGenerating animated cursor pixmaps... DONE"



echo -ne "Generating cursor theme...\\r"
for CUR in src/config/*.cursor; do
	BASENAME="${CUR##*/}"
	BASENAME="${BASENAME%.*}"

	if ! ERR="$(xcursorgen -p "$PIXMAPS" "$CUR" "$OUTPUT/cursors/$BASENAME" 2>&1)"; then
		echo "FAIL: $CUR $ERR"
		exit 2
	fi
done
echo "Generating cursor theme... DONE"



echo -ne "Copying SVG metadata...\\r"
for JSON in "$METADATA/"*.json; do
	BASENAME="${JSON##*/}"
	BASENAME="${BASENAME%.*}"
	
	cp "$JSON" "$OUTPUT/cursors_scalable/$BASENAME/metadata.json"
done
echo "Copying SVG metadata... DONE"



echo -ne "Copying SVGs...\\r"
for SVG in "$SVGS/"*.svg; do
	BASENAME=${SVG##*/}
	BASENAME="${BASENAME%.*}"
	
	if [[ "$BASENAME" =~ -[0-9]{2}$ ]]; then
		DIRNAME="${BASENAME%-*}"
	else
		DIRNAME="$BASENAME"
	fi
	
	cp "$SVG" "$OUTPUT/cursors_scalable/$DIRNAME/$BASENAME.svg"
done
echo "Copying SVGs... DONE"



echo -ne "Generating shortcuts...\\r"
while read -r ALIAS ; do
	FROM=${ALIAS% *}
	TO=${ALIAS#* }

	[ -e "$OUTPUT/cursors/$FROM" ] && continue

	ln -s "$TO" "$OUTPUT/cursors/$FROM"
	ln -s "$TO" "$OUTPUT/cursors_scalable/$FROM"
done < $ALIASES
echo "Generating shortcuts... DONE"



echo -ne "Copying Theme Index...\\r"
[ -e "$OUTPUT/$INDEX" ] || cp $INDEX "$OUTPUT/index.theme"
echo "Copying Theme Index... DONE"



echo -ne "Compressing to tarball...\\r"
BASENAME=${OUTPUT##*/}
tar -cJf "$OUTPUT.tar.xz" -C "$OUTPUT/.." "$BASENAME"
echo "Compressing to tarball... DONE"


echo "COMPLETE!"
