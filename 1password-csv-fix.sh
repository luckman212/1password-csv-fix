#!/usr/bin/env bash

#prereqs
for c in jq op fzf ; do
  if ! hash $c &>/dev/null; then echo "requirement missing: $c"; exit 1; fi
done

FB=$(printf '\x01\e[1m\x02')
FN=$(printf '\x01\e[0m\x02')
FR=$(printf '\x01\e[1;31m\x02')
FG=$(printf '\x01\e[1;32m\x02')
GC="${FG}✔${FN}"
RX="${FR}✘${FN}"
TEMP_DIR='/tmp'
FZF_OPTS=(
	--exact
	--no-mouse
	--no-select-1
	--no-hscroll
	--bind='ctrl-a:select-all,ctrl-s:deselect-all'
	--exit-0
)

_usage() {
	cat <<-EOF
	usage: ${0##*/} [opts]
	    -a,--all                  show all items (tab-separated: ID, Name, URL)
	    -g,--get                  get JSON for a single item
	    -s,--search <query>       search (regex, within URL)
	    -o,--open <item>          open item in 1Password UI
	    -e,--edit [item]          edit item in 1Password UI (use \`last\` for MRU)
	    -u,--urls [item]          show URLs (if no item arg is supplied, show all)
	    -l,--long                 list items with invalid CSV URLs
	    -r,--raw                  raw JSON output of \`item list\`
	    --fix <item>              repair invalid comma-separated URLs from CSV import
	    --fix-multi               use fzf to select multiple items (to fix)
	    --del-multi               use fzf to DELETE multiple items
	    --del-field <fieldname>   recursively remove a field (if empty) from multiple items
	EOF
}

_is_json() {
	case $1 in
		--arg)
			[[ -n $2 ]] || return 1
			jq &>/dev/null <<<"$2" '.'
			return $?
			;;
		--file)
			[[ -e $2 ]] || return 1
			jq &>/dev/null '.' "$2"
			return $?
			;;
		*)
			echo "specify --arg or --file"
			return 1
			;;
	esac
}

_authorize() {
	eval "$(op account list --format=json | jq --raw-output '.[0] | @sh "a=\(.account_uuid) h=\(.url)"')"
	v=$(op vault list --format=json | jq --raw-output '.[0].id // empty')
}

_getAllItems() {
	op item list --format=json | jq 'sort_by(.title | ascii_upcase)'
}

_getItem() {
	[[ -n $1 ]] || return 1
	op item get "$1" --format=json
}

_getUrls() {
	[[ -n $1 ]] || return 1
	_getItem "$1" |
	jq --raw-output '.urls[] |
	"\(if .primary then "primary" else .label end): \(.href)"'
}

_getAllUrls() {
	local MAX_COLS
	MAX_COLS=$(tput cols)
	MAX_COLS=${MAX_COLS:-80}
	(( MAX_COLS -= 10 ))
	_getAllItems |
	jq --raw-output --argjson m "$MAX_COLS" 'map({id, title, urls})[] |
	"\(.id)\t\(.title)",
	(.urls[]? | "\t\(.label // "*") \(.href[:$m])") // "\t(no urls)"'
}

_op() {
	_authorize
	i=$1
	#open "https://start.1password.com/open/i?a=$a&h=$h&i=$i&v=$v"
	open "onepassword://$action/?a=$a&v=$v&i=$i"
}

_all() {
	_getAllItems |
	jq --raw-output '.[] | [
		.id,
		.title,
		(if .urls[0].href
		then .urls[0].href|split("/")[2]
		else "-" end) ] | @tsv'
}

_search() {
	_getAllItems |
	jq --raw-output --arg s "$1" '
		map(select((.urls[]?.href | test($s))))[] | [
			.id,
			.title,
			(if .urls[0].href
			then .urls[0].href|split("/")[2]
			else "-" end)
		] | @tsv'
}

_fix() {
	local url_count
	[[ -n $1 ]] || return 1
	item_json=$(_getItem "$1")
	_is_json --arg "$item_json" || return 1
	echo "$1" >"$TEMP_DIR/1p-mru"
	url_count=$(jq '.urls | length' <<< "$item_json")
	(( url_count == 1 )) || { echo "incorrect url count ($url_count)"; return 1; } #abort if url count != 1
	url0_count=$(jq '.urls[0].href | split(",") | length' <<< "$item_json")
	(( url0_count > 1 )) || { echo "url0 not in csv format"; return 1; } #abort if url0 is not comma separated
	f="$TEMP_DIR/$1.json"
	[[ -e $f ]] && rm "$f"
	_getItem "$1" |
	jq >"$f" '
	def split_urls(href):
		href | split(",") | map({
			label: "website",
			href: .
		});
	.urls |= ([{
		primary: .[0].primary,
		href: .[0].href | split(",")[0]
	}] +
	(split_urls(.[0].href) | .[1:]))'
	if _is_json --file "$f" ; then
		res=$(op item edit "$1" --template="$f")
		rc=$?
		if (( rc > 0 )); then
			echo "$1 ${RX}"
			echo "$res"
			exit 1
		else
			echo "$1 ${GC}"
			rm "$f"
			if [[ $MULTI != true ]]; then
				action='view-item'
				_op "$1"
			fi
		fi
	fi
}

_longurls() {
	_getAllItems |
	jq --raw-output 'map(select((.urls[]?.href | test(","))))[] |
	[ .id, (.title|col(25)), .urls[0].href ] | @tsv'
}

_allitems_raw() {
	_getAllItems |
	jq --raw-output '.[] | [
		.id,
		(.title|col(25)),
		(if .urls[0].href
			then .urls[0].href|split(",")[0]
			else "-" end)
		] | @tsv'
}

_uiAction() {
	if [[ -n $1 ]]; then
		if [[ $1 == 'last' ]] && [[ -e $TEMP_DIR/1p-mru ]]; then
			_op "$(<$TEMP_DIR/1p-mru)"
		else
			_op "$1"
		fi
	else
		read -r ITEM _ < <(_allitems_raw | fzf "${FZF_OPTS[@]}" --no-multi --header "${action^^}")
		_op "$ITEM"
	fi
}

case $1 in
	-h|--help|'') _usage; exit;;
	-a|--all) _all; exit;;
	-g|--get) shift; _getItem "$1"; exit;;
	-s|--search) shift; _search "$1"; exit;;
	-o|--open) shift; action='view-item'; _uiAction "$1"; exit;;
	-e|--edit) shift; action='edit-item'; _uiAction "$1"; exit;;
	-el) shift; action='edit-item'; _uiAction last; exit;;
	-u|--urls)
		shift
		if [[ -n $1 ]]; then
			_getUrls "$1"
		else
			_getAllUrls
		fi
		exit
		;;
	-l|--long) _longurls; exit;;
	-r|--raw) _getAllItems; exit;;
	--fix) shift; _fix "$1"; exit;;
	--fix-multi) shift; MULTI=true;
		while read -r -u3 ITEM _ ; do
			#echo "trying to fix $ITEM"
			if ! _fix "$ITEM"; then
				exit 1
			fi
		done 3< <(_longurls | fzf "${FZF_OPTS[@]}" --multi --header "FIX")
		exit
		;;
	--del-multi) shift; MULTI=true;
		while read -r -u3 ITEM REST ; do
			echo "deleting ${ITEM}: $REST"
			if ! op item delete "$ITEM" --archive ; then
				exit 1
			fi
		done 3< <(_allitems_raw | fzf "${FZF_OPTS[@]}" --multi --header "DELETE")
		exit
		;;
	--del-field)
		shift
		[[ -n $1 ]] || { echo "specify the field name"; exit 1; }
		FIELD_TO_DELETE=$1
		read -r -p "${FR}CONFIRM:${FN} delete the \`${FB}${FIELD_TO_DELETE}${FN}\` field (if empty) from multiple items? [y/N] " ANSWER
		[[ ${ANSWER,,} != "y" ]] && exit
		c=0
		while IFS=$'\t' read -r -u3 ITEM NAME _ ; do
			cur=$(_getItem "$ITEM")
			[[ -n $cur ]] || { echo 1>&2 "error processing $ITEM"; continue; }
			NAME=$(sed 's/ *$//' <<<"$NAME")
			has_field=$(jq <<<"$cur" --arg f "${FIELD_TO_DELETE^^}" '.fields[] | if (.label|ascii_upcase) == $f then true else empty end')
			field_contents=$(jq <<<"$cur" --arg f "${FIELD_TO_DELETE^^}" '.fields[] | select((.label|ascii_upcase) == $f) | .value // empty')
			if [[ $has_field != true ]]; then
				echo "${FB}${NAME}${FN} does not have the $FIELD_TO_DELETE field"
				continue
			fi
			if [[ -n $field_contents ]]; then
				echo "${FR}skipping ${NAME} because the $FIELD_TO_DELETE field is not empty${FN}"
				continue
			fi
			echo -n "deleting $FIELD_TO_DELETE from ${ITEM}: ${NAME} "
			f="$TEMP_DIR/${ITEM}.json"
			[[ -e $f ]] && rm "$f"
			jq --arg f "${FIELD_TO_DELETE^^}" '.fields |= map(select(((.label|ascii_upcase)==$f)|not))' <<<"$cur" >"$f"
			if _is_json --file "$f" ; then
				res=$(op item edit "$ITEM" --template="$f")
				rc=$?
				if (( rc > 0 )); then
					echo "${RX}"
					echo "$res"
					exit 1
				else
					(( c++ ))
					LAST=$ITEM
					echo "${GC}"
					rm "$f"
				fi
			fi
		done 3< <(_allitems_raw | fzf "${FZF_OPTS[@]}" --multi --header "DELETE FIELD: ${FIELD_TO_DELETE}")
		if (( c == 1 )); then
			action='view-item'
			_op "$LAST"
		fi
		exit
esac
