#!/usr/bin/env bash
#
# Build script to build Nordic Cursors Scalable Theme

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
THREADS="${THREADS:=$(nproc)}"
RAWSVG="src/cursors.svg"
INDEX="src/index.theme"
ALIASES="src/cursorList"
METADATA="src/metadata"


echo -ne "Checking Requirements...\\r"
if [ ! -f $RAWSVG ]; then
	echo -e "\\nFAIL: '$RAWSVG' missing in /src" >&2
	exit 1
fi

if [ ! -f $INDEX ]; then
	echo -e "\\nFAIL: '$INDEX' missing in /src" >&2
	exit 1
fi

if ! type "inkscape" >/dev/null; then
	echo -e "\\nFAIL: inkscape must be installed" >&2
	exit 1
fi

if ! type "xcursorgen" >/dev/null; then
	echo -e "\\nFAIL: xcursorgen must be installed" >&2
	exit 1
fi

if ! type "svgcleaner" >/dev/null; then
	echo -e "\\nFAIL: svgcleaner must be installed" >&2
	exit 1
fi

if ! type "scour" >/dev/null; then
	echo -e "\\nFAIL: scour must be installed" >&2
	exit 1
fi
echo "Checking Requirements... DONE"



echo -ne "Making Folders...\\r"
RESOLUTIONS="$(cat src/config/*/*.cursor | cut -d ' ' -f 1 | sort -u)"
PIXMAPS="build/pixmaps"
SVGS="build/svg"
OUTPUT_BASEDIR="$(grep -oP "(?<=Name\=).*$" "$INDEX" | tr '[:upper:] ' '[:lower:]_')"

declare -A OUTPUTS
OUTPUTS[default]="build/$OUTPUT_BASEDIR"

while IFS= read -r VARIANT; do
	OUTPUTS[$VARIANT]="build/${OUTPUT_BASEDIR}_${VARIANT}"
done < <(find src/config/* -maxdepth 0 -type d -not -name default -printf '%f\n')

for OUT in "${OUTPUTS[@]}"; do
	mkdir -p "$OUT/cursors"
	mkdir -p "$OUT/cursors_scalable"
done

for RES in $RESOLUTIONS; do
	mkdir -p "$PIXMAPS/${RES}px"
done

mkdir -p "$SVGS"

for JSON in "$METADATA/"*.json; do
	BASENAME="${JSON##*/}"
	BASENAME="${BASENAME%.*}"
	for OUTPUT in "${OUTPUTS[@]}"; do
		mkdir -p "$OUTPUT/cursors_scalable/$BASENAME"
	done
done
echo 'Making Folders... DONE';



for CUR in src/config/default/*.cursor; do
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



function make_optimized_svg() {
	inkscape -i "$1" "$RAWSVG" \
		--actions="select-all:all;unselect-by-id:${1}-cursor;selection-hide" \
		--export-background-opacity=0 \
		--export-type=svg \
		--export-plain-svg \
		--export-filename="$SVGS/$1.svg"

	svgcleaner "$SVGS/$1.svg" "$SVGS/$1.svg" 2>/dev/null

	inkscape "$SVGS/$1.svg" \
		--actions="select-all:all;object-to-path$(printf ';select-all:groups;selection-ungroup%.0s' $(seq 1 5))" \
		--export-type=svg \
		--export-plain-svg \
		--export-filename="$SVGS/$1.svg"

	scour "$SVGS/$1.svg" "$SVGS/$1-tmp.svg" >/dev/null
	mv "$SVGS/$1-tmp.svg" "$SVGS/$1.svg"
	svgcleaner --indent 2 "$SVGS/$1.svg" "$SVGS/$1.svg" 2>/dev/null
}



for CUR in src/config/*/*.cursor; do
	BASENAME="${CUR##*/}"
	BASENAME="${BASENAME%.*}"

	echo -ne "\033[0KGenerating optimized SVGs... $BASENAME\\r"

	[ "$SVGS/$BASENAME.svg" -ot $RAWSVG ] && make_optimized_svg "$BASENAME"
done
echo -e "\033[0KGenerating optimized SVGs... DONE"



for i in $(seq -w 1 23); do
	echo -ne "\033[0KGenerating animated optimized SVGs... $i / 23 \\r"
	
	for ANI in progress wait; do
		[ "$SVGS/$ANI-$i.svg" -ot $RAWSVG ] && make_optimized_svg "$ANI-$i"
	done
done
echo -e "\033[0KGenerating animated optimized SVGs... DONE"



echo -ne "Generating cursor theme...\\r"
for VARIANT in "${!OUTPUTS[@]}"; do
	for CUR in "src/config/$VARIANT"/*.cursor; do
		BASENAME="${CUR##*/}"
		BASENAME="${BASENAME%.*}"

		if ! ERR="$(xcursorgen -p "$PIXMAPS" "$CUR" "${OUTPUTS[$VARIANT]}/cursors/$BASENAME" 2>&1)"; then
			echo "FAIL: $CUR $ERR" >&2
			exit 2
		fi
	done
done
echo "Generating cursor theme... DONE"



echo -ne "Copying SVG metadata...\\r"
for JSON in "$METADATA/"*.json; do
	BASENAME="${JSON##*/}"
	BASENAME="${BASENAME%.*}"

	for OUTPUT in "${OUTPUTS[@]}"; do
		cp "$JSON" "$OUTPUT/cursors_scalable/${BASENAME}/metadata.json"
	done
done
echo "Copying SVG metadata... DONE"



echo -ne "Copying SVGs...\\r"
for SVG in "$SVGS/"*.svg; do
	BASENAME="${SVG##*/}"
	BASENAME="${BASENAME%.*}"

	if [[ "$BASENAME" =~ -[0-9]{2}$ ]]; then
		DIRNAME="${BASENAME%-*}"
	else
		DIRNAME="$BASENAME"
	fi

	for OUTPUT in "${OUTPUTS[@]}"; do
		cp "$SVG" "$OUTPUT/cursors_scalable/$DIRNAME/$BASENAME.svg"
	done
done
echo "Copying SVGs... DONE"



echo -ne "Generating shortcuts...\\r"
while read -r ALIAS ; do
	FROM="${ALIAS% *}"
	TO="${ALIAS#* }"

	for OUTPUT in "${OUTPUTS[@]}"; do
		[ -e "$OUTPUT/cursors/$FROM" ] && continue

		ln -s "$TO" "$OUTPUT/cursors/$FROM"
		ln -s "$TO" "$OUTPUT/cursors_scalable/$FROM"
	done
done < $ALIASES
echo "Generating shortcuts... DONE"



echo -ne "Copying Theme Index...\\r"
for OUTPUT in "${OUTPUTS[@]}"; do
	[ -e "$OUTPUT/$INDEX" ] || cp $INDEX "$OUTPUT/index.theme"
	cp LICENSE "$OUTPUT/LICENSE"
	cp README.md "$OUTPUT/README.md"
done
echo "Copying Theme Index... DONE"



echo -ne "Compressing to tarball...\\r"
for OUTPUT in "${OUTPUTS[@]}"; do
	BASENAME="${OUTPUT##*/}"
	tar -cJf "$OUTPUT.tar.xz" -C "$OUTPUT/.." "$BASENAME"
done
echo "Compressing to tarball... DONE"


echo "COMPLETE!"
