
I_PATH=~/i
I_SOURCE_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
I_GPT_VERSION="${I_GPT_VERSION:=gpt-4}"

complete -F __i_completion i

since=""

# default entrypoint for the i command
function i {

	# select command name, if none are recognised then we're writing a journal entry. 
	case "${1}" in

		"amend") # overwrite the last message - useful in case of missing info or typo's
			shift
			__i_amend "$@"; return;;

		"log" ) # list out the journal
			shift
			__i_list "$@"; return;;

		"list" ) # list out the journal
			shift
			__i_list "$@"; return;;

		"mentioned") # list out names mentioned
			shift

			if [ "${1}" == "" ]; then
				__i_mentioned;
			else
				__i_mentioned_someone "${1}";
			fi

			return;;

		"tagged") # list out tags tagged
			shift

			if [ "${1}" == "" ]; then
				__i_tagged;
			else
				__i_tagged_something "${1}";
			fi
			return;;

		"find") # generic find for anything
			shift

			__i_find "$*"
			return;;

		"occurrences") # count occurrences of anything
			shift

			__i_count_occurrences "$@"
			return;;

		"git" ) # run arbitrary git commands on the i repo
			shift

			git -C $I_PATH/ "$@"; return;;

		"today") # view todays journal entries with a special date format, paginated
			shift

			git -C $I_PATH/ log --since "1am"  --pretty=format:"%Cblue%cd (%cr): %Creset%B" --date=format:"%H:%M" | fmt | less
			return;;

		"yesterday") # view yesterdays journal entries with a special date format, paginated
	
			# i'm using this until i've implemented 'until'
			git -C $I_PATH/ log --since "2 days ago" --until midnight  --pretty=format:"%Cblue%cd: %Creset%B" --date=format:"%H:%M" | fmt | less
			return;;

		"digest") # use gpt to summarise the weeks activity into a digest
			__i_digest
			return;;

		"remember") # use gpt to generate a todo list of tasks that sound like they are outstanding from the previous week
			__i_remember
			return;;

		"analyse")
			shift

			__i_analyse "$@"
			return;;

		"analyze")
			shift

			__i_analyse "$@"
			return;;

		"import")
			shift

			__i_import "$@"
			return;;

		"upgrade") # upgrade the 'i' client
			git -C $I_SOURCE_DIR pull
			source $I_SOURCE_DIR/i.sh
			return;;

		
		"help") # Display help
			__i_help
			return;;
		
		"--help") # Display help
			__i_help
			return;;
		
		"-h") # Display help
			__i_help
			return;;

	esac

	if [ ! -n "${1}" ]; then
		__i_help
		return
	fi

	# add a journal entry
	__i_write "$@"
}

# basic help function
function __i_help {
  echo "Usage: i [COMMAND|MESSAGE]"
  echo ""
  echo "COMMANDS:"
  echo "  amend            Overwrite the last message - useful in case of missing info or typos."
  echo "  list             List out the journal."
  echo "  mentioned        List out names mentioned or entries where a specific person is mentioned."
  echo "  tagged           List out tags mentioned or entries where a specific tag is mentioned."
  echo "  find             Generic find for anything."
  echo "  occurrences      Count occurrences of anything."
  echo "  git              Run arbitrary git commands on the 'i' repo."
  echo "  today            View today's journal entries with a special date format, paginated."
  echo "  yesterday        View yesterday's journal entries with a special date format, paginated."
  echo "  digest           Use GPT to summarize the week's activity into a digest."
  echo "  remember         Use GPT to generate a to-do list of tasks that sound outstanding from the previous week."
  echo "  analyse          Run arbitrary GPT analysis commands on a specific time window from the journal."
  echo "  import           Import git history into journal for the currently configured git user."
  echo "  upgrade          Upgrade the 'i' client."
  echo "  help(-h|--help)  Display this help for the 'i' command."
  echo ""
  echo "By default, if none of the recognized commands are used, a new journal entry is created with the provided message."
  echo ""
  echo "For more detailed information on each command, look at the source of 'i.sh'."
}

# write a (potentially empty) commit with a message
function __i_write {
	HOOKS_PATH="$(git config core.hooksPath)"
	git config core.hooksPath .git/hooks
	git  -C $I_PATH/ commit --allow-empty -qam "$*"
	git config core.hooksPath "$HOOKS_PATH"

	# If we have a remote, push to it async
	if [ -n "$(git  -C $I_PATH/ remote show | grep origin)" ]; then
		( git  -C $I_PATH/ push -u origin main -q > /dev/null 2>&1 & );
	fi
}

# amend the previous message
function __i_amend {
	HOOKS_PATH="$(git config core.hooksPath)"
	git config core.hooksPath .git/hooks
	git  -C $I_PATH/ commit --allow-empty --amend -qam "$*"
	git config core.hooksPath "$HOOKS_PATH"

	# If we have a remote, push to it async
	if [ -n "$(git  -C $I_PATH/ remote show | grep origin)" ]; then
		( git  -C $I_PATH/ push -u origin main -f -q > /dev/null 2>&1 & );
	fi
}

# list the entries in readable format
# the syntax is `i list` or 
# the syntax is `i list since "last monday" until "yesterday"`
function __i_list {
	item="${1}"
	local until_cmd since_cmd

	while [ "$item" == "until" ] || [ "$item" == "since" ] && [ -n "${2}" ]; do
		if [ "$item" == "until" ]; then
			until_cmd="${2}"
		elif [ "$item" == "since" ]; then
			since_cmd="${2}"
		fi
		shift 2
		item="${1}"
	done

	git -C $I_PATH/ log --since "${since_cmd:=1970}" --until "${until_cmd:=now}" --pretty=format:"%Cblue%cr: %Creset%B";
}

function __i_count_occurrences {
	__i_list | sed 's/\ /\n/g' | grep ${1} --color=never | sed 's/,//g; s/\.//g' | sort | uniq -c | sort -rh
}

# list the names mentioned
function __i_mentioned {
	__i_count_occurrences @
}

# lists entries where a specific person is mentioned
function __i_mentioned_someone {
	__i_find @${1}
}

# list the tags mentioned
function __i_tagged {
	__i_count_occurrences %
}

# lists entries where a specific tag is mentioned
function __i_tagged_something {
	__i_find %${1}
}

# basic search across the results
function __i_find {
	__i_list | grep "${1}"
}

# run arbitrary GPT analysis commands on a specific time window from the journal
# the syntax is `i analyse since "last monday" until "yesterday" list all people i interacted with`
function __i_analyse { 
	item="${1}"
	local until_cmd since_cmd

	while [ "$item" == "until" ] || [ "$item" == "since" ] && [ -n "${2}" ]; do
		if [ "$item" == "until" ]; then
			until_cmd="${2}"
		elif [ "$item" == "since" ]; then
			since_cmd="${2}"
		fi
		shift 2
		item="${1}"
	done

	# the journal
	OUT=$(git -C $I_PATH/ log --since "${since_cmd:=1970}" --until "${until_cmd:=now}" --pretty=format:"%cd: %B" | tr -d '"\n')
	# the whole prompt
	PROMPT="$* \n\n\n "$OUT""

	curl -X POST -s --no-buffer \
	-H "Content-Type: application/json" \
	-H "Authorization: Bearer $GPT_ACCESS_TOKEN" \
	-d '{
		"model": "'"$I_GPT_VERSION"'",
		"stream": true,
		"temperature": 0,
		"frequency_penalty": 1.0,
		"messages": [
			{
				"role": "user", 
				"content": "'"$PROMPT"'"
			}
		]
	}' \
	https://api.openai.com/v1/chat/completions | __i__server_push_to_stdout
}

# import all commits by git user in git repo into the journal, then reorder the entire journal by author date
# TODO - allow providing since & until dates to limit the import to a specific time window
# TODO - currently pushes very first commit to bottom of dev log. may not be desirable
# TODO - not tested very well, probably doesn't 100% work
function __i_import {
	# could support user as an argument, but for now just use the current git user since that is the most common use case
	##
	# check for .git folder to ensure we are in a git repo
	if [ ! -d .git ]; then
		echo "ERROR: ${PWD##*/} does not appear to be the root of a git repo"
		return
	fi

	# FIXME - I think this is broken, it's still running hooks even when trying to disable them.
	#			must manually remove hook configuration from .git/config for now
	HOOKS_PATH="$(git config core.hooksPath)"
	git config core.hooksPath .git/hooks

	local TRUNK_BRANCH
	TRUNK_BRANCH=$(git -C "${I_PATH}" branch --show-current)
	
	# check if our log is on a valid trunk branch
	if [ "$TRUNK_BRANCH" != "master" ] && [ "$TRUNK_BRANCH" != "main" ]; then
		echo "ERROR: ${PWD##*/} appears to be on branch $TRUNK_BRANCH, not master or main. Continue?"
		read -p "Continue? [y/N] " -n 1 -r
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			return
		fi
	fi

	# Check to make sure we actually have commits to import before kicking off the job
	# use: git rev-list  --author="$(git config user.name)"  --count HEAD --all
	if [ -z "$(git rev-list  --author="$(git config user.name)"  --count HEAD --all)" ]; then
		echo "ERROR: ${PWD##*/} appears to have no commits to import for user $(git config user.name)"
		return
	fi

	# check if we see evidence of this repository already being in the journal
	# by searching for [repo:REPO_NAME] in the journal
	if [ -n "$(git -C "$I_PATH/" log --pretty=format:"%B" 2>&1 | grep "\[repo:${PWD##*/}\]")" ]; then
		echo "ERROR: ${PWD##*/} already appears to be in the journal! Continue?"
		read -p "Continue? [y/N] " -n 1 -r
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			return
		fi
	fi

	# back-up trunk of log
	git -C "${I_PATH}" checkout -b "$TRUNK_BRANCH-backup-$(date +%s)"
	git -C "${I_PATH}" push origin "$TRUNK_BRANCH-backup-$(date +%s)"

	# locals
	local TMP_BRANCH TMP_BRANCH_REORDER
	TMP_BRANCH="${PWD##*/}-temp"
	TMP_BRANCH_REORDER="${PWD##*/}-temp-reorder"

	# checkout temporary branch
	git -C "${I_PATH}" checkout -b "$TMP_BRANCH"

	# $(printf '%s\n' ${PWD##*/}) - more reliable than echo or basename approach
	git log --author="$(git config user.name)" --reverse --pretty=format:"%ad|$(printf '%s\n' ${PWD##*/})|%S|%s" --all |
	while IFS='|' read -r commitTime repoName branchName commitMessage; do
		# Set the date for the new commit
		GIT_AUTHOR_DATE="$commitTime" GIT_COMMITTER_DATE="$commitTime" \
		git -C "${I_PATH}" commit --allow-empty -qam "[repo:$repoName] (branch:$branchName) cmsg: '$commitMessage'"
	done

	# log out commit messages between current branch HEAD and second commit
	# test cmd: git -C "${I_PATH}" log --reverse --pretty=format:"%H" --author-date-order $SECOND_COMMIT..HEAD

	local FIRST_COMMIT SECOND_COMMIT CURR_HEAD
	FIRST_COMMIT=$(git -C "${I_PATH}" log --reverse --format='%H' | head -n 1)
	SECOND_COMMIT=$(git -C "${I_PATH}" log --reverse --format='%H' | sed -n '2 p')
	CURR_HEAD=$(git -C "${I_PATH}" log --format='%H' | head -n 1)

	# check out first commit
	git -C "${I_PATH}" checkout $FIRST_COMMIT

	# Create a temporary branch to store the reordered commits
	git -C "${I_PATH}" checkout -b "$TMP_BRANCH_REORDER"

	# Reorder when the commits were made by author date for the entire repository
	git -C "${I_PATH}" log $SECOND_COMMIT..$CURR_HEAD --pretty=format:"%ad|%s" --date=iso | sort | while IFS='|' read -r commitTime commitMessage; do 
		git -C "${I_PATH}" commit --allow-empty --date="$commitTime" -qam "$commitMessage";
	done

	git -C "${I_PATH}" filter-branch -f --env-filter 'export GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"'

	# Replace the original branch with the reordered branch
	# TODO - get the appropriate 'main' branch using whatever the current branch is
	git -C "${I_PATH}" branch -f "${TRUNK_BRANCH}" "$TMP_BRANCH_REORDER"
	git -C "${I_PATH}" checkout "${TRUNK_BRANCH}"
	git -C "${I_PATH}" branch -D "$TMP_BRANCH_REORDER"
	git -C "${I_PATH}" branch -D "$TMP_BRANCH"
	git -C "${I_PATH}" push origin "${TRUNK_BRANCH}" --force

	# Revert hooks path
	git config core.hooksPath "$HOOKS_PATH"
}

# use gpt to summarise the weeks activity into a digest
function __i_digest {
	OUT=$(git -C $I_PATH/ log --since "7 days ago" --pretty=format:"%cr: %B" | tr -d '"\n')

	curl -X POST -s --no-buffer \
	-H "Content-Type: application/json" \
	-H "Authorization: Bearer $GPT_ACCESS_TOKEN" \
	-d '{
		"model": "'"$I_GPT_VERSION"'",
		"stream": true,
		"temperature": 0,
		"frequency_penalty": 1.0,
		"messages": [
			{
				"role": "user", 
				"content": "summarise the notes below into MARKDOWN sections about distinct subjects in order for me to give a weekly update. double check there are the minimum possible number of subjects, for example, do not create a header called `RPC Tooling` if an `RPC` header also exists, and so on. the format should be TITLE OF SUBJECT followed by BULLET LIST OF SUBJECT ENTRIES. do not include entries that simply state a conversation took place with no other detail unless it is the only item within a section. remove any @ symbols at the start of names. always make names bold text. if a word starts with a % then use that word as the subject title. be as concise as possible with each bullet point without losing significant points of information and do not omit instances of work that took place.  after you have generated the full list, generate a footer section which outlines EVERY individual activity that took place that week.  after that section, please make note of EVERY person I spoke to along with the number of times I spoke to them AND a sentiment analysis of our interactions scoring 0-10. \n\n\n'"$OUT"'"
			}
		]
	}' \
	https://api.openai.com/v1/chat/completions | __i__server_push_to_stdout
}

# use gpt to generate a todo list of tasks that sound like they are outstanding from the previous week
function __i_remember {
	OUT=$(git -C $I_PATH/ log --since "7 days ago" --pretty=format:"%cr: %B" | tr -d '"\n')

	curl -X POST -s --no-buffer \
	-H "Content-Type: application/json" \
	-H "Authorization: Bearer $GPT_ACCESS_TOKEN" \
	-d '{
		"model": "'"$I_GPT_VERSION"'",
		"stream": true,
		"temperature": 0,
		"frequency_penalty": 0.38,
		"presence_penalty": 0.38,
		"messages": [
			{
				"role": "user", 
				"content": "I want you to generate a todo list of tasks that sound like they are outstanding in the following journal entries from last week. I am not asking for a todo list based on every single item - it is ok for there to be no items at all. I specifically want to identify tasks which sound like they are not resolved, so I can pick them up after the report is generated. please take into account the date at the start of each entry  and figure out based on that whether tasks were being resolved throughout the week. Only raise tasks you KNOW are unresolved, do not guess - when you see language such as \"i need to\" for example.  do not include actions other people have taken. DO NOT output line numbers. DO NOT output a title, just a bullet list.  \n\n\n'"$OUT"'"
			}
		]
	}' \
	https://api.openai.com/v1/chat/completions | __i__server_push_to_stdout | fzf -m --header "Select using TAB >"
}

# used to parse the server push messages in the completions response and output them to stdout
function __i__server_push_to_stdout { 
	awk -F "data: " '/^data: /{print $2; fflush()}'| \
	python3 -c "
import sys
import json

for line in sys.stdin:
	try:
		data = json.loads(line).get('choices')[0].get('delta').get('content')
		if data is not None:
			print(data, end='', flush=True)
	except json.JSONDecodeError:
		pass  # ignore lines that are not valid JSON
"
}

# used to create a list of unique occurrences of a specific character
function __i_unique_occurrences_completion {
	__i_list | sed 's/\ /\n/g' | grep ${1} --color=never | sed 's/,//g; s/\.//g' | sort | uniq | grep -e "^${1}[a-zA-Z0-9\-][a-zA-Z0-9\-]*" --color=never | sort -rh | tr '\n' ' ' | tr -d \'\"
}

# used to power tab completion for the @ and % characters & default
function __i_completion {
	local cur_word
	cur_word="${COMP_WORDS[COMP_CWORD]}"

	local words
	words="amend list mentioned tagged find occurrences git upgrade today yesterday digest import remember analyse"

	case $cur_word in
	@*) words=$(__i_unique_occurrences_completion @ | sed 's/@[^A-Za-z0-9]//g' ) ;;
	%*) words=$(__i_unique_occurrences_completion % | sed 's/@[^A-Za-z0-9]//g' ) ;;
	esac

	COMPREPLY+=($(compgen -W "${words}" "${COMP_WORDS[COMP_CWORD]}"))
}


# do an init of the i repo if we detect it isn't there
if [ ! -e "$I_PATH" ]; then
	mkdir -p $I_PATH
	git -C $I_PATH/ init -q
	__i_write 'created a journal'
fi

# Check if the script is being executed directly. If so, we run i directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
	i "$@"
fi
