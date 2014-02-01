#!/bin/bash
#Created by Sam Gleske
#MIT License
#Created Tue Sep 10 23:01:08 EDT 2013
#USAGE
#  ./add_mirror.sh --git --project-name someproject --mirror http://example.com/project.git

#bash option stop on first error
set -e

#Include all user options and dependencies
git_mirrors_dir="${0%/*}"
. "${git_mirrors_dir}/config.sh"
. "${git_mirrors_dir}/lib/VERSION"
. "${git_mirrors_dir}/lib/functions.sh"

#export env vars for python script
export gitlab_user_token_secret gitlab_url gitlab_namespace gitlab_user ssl_verify

PROGNAME="${0##*/}"
PROGVERSION="${VERSION}"

#Default script options
svn=false
git=false
bzr=false
project_name=""
mirror=""
force=false

#
# ARGUMENT HANDLING
#

usage()
{
  cat <<EOF
${PROGNAME} ${PROGVERSION} - MIT License by Sam Gleske

USAGE:
  ${PROGNAME} TYPE --project NAME --mirror URL [--authors-file FILE]

DESCRIPTION:
  This will add a git or SVN repository to be mirrored by GitLab.  It 
  first checks to see if the project exists in gitlab.  If it does
  not exist then it creates it.  It will then clone and check in the
  first copy into GitLab.  From there you must use the update_mirror.sh
  script or git git-mirrors.sh script.

  -h,--help          Show help

  -v,--version       Show program version

  --authors-file FILE
                     An authors file to pass to git-svn for mapping
                     SVN users to git users.

  -f,--force         Force add project even if it already exists.
                     Any program errors will automatically continue.

  -m,--mirror URL    Repository URL to be mirrored.

  -n,--no-create URL Set a static remote without attempting to resolve
                     the remote in GitLab.  This allows more generic
                     mirroring without needing to be specifically for
                     GitLab.

  -p,--project-name NAME
                     Set a GitLab project name to NAME.

REPOSITORY TYPES:
  At least one repository TYPE is required.

  --bzr              Mirror a Bazaar repository (must be explicitly set)

  --git              Mirror a git repository (must be explicitly set)

  --svn              Mirror a SVN repository (must be explicitly set)

EOF
}
#Short options are one letter.  If an argument follows a short opt then put a colon (:) after it
SHORTOPTS="hvfm:n:p:"
LONGOPTS="help,version,force,git,svn,bzr,mirror:,no-create:,project-name:,authors-file:"
ARGS=$(getopt -s bash --options "${SHORTOPTS}" --longoptions "${LONGOPTS}" --name "${PROGNAME}" -- "$@")
eval set -- "$ARGS"
while true; do
  case $1 in
    -h|--help)
        usage
        exit 1
      ;;
    -v|--version)
        echo "${PROGNAME} ${PROGVERSION}"
        exit 1
      ;;
    --git)
        git=true
        shift
      ;;
    --svn)
        svn=true
        shift
      ;;
    --bzr)
        bzr=true
        shift
      ;;
    -f|--force)
        force=true
        set +e
        shift
      ;;
    -p|--project-name)
        project_name="${2}"
        shift 2
      ;;
    -m|--mirror)
        mirror="${2}"
        shift 2
      ;;
    -n|--no-create)
        no_create="${2}"
        shift 2
      ;;
    --authors-file)
        authors_file="${2}"
        shift 2
      ;;
    --)
        shift
        break
      ;;
    *)
        shift
      ;;
    esac
done

#
# Program functions
#

function preflight() {
  STATUS=0
  #test for multiple repository types
  types=0
  selected_types=()
  if ${git};then
    ((types += 1))
    selected_types+=('--git')
  fi
  if ${svn};then
    ((types += 1))
    selected_types+=('--svn')
  fi
  if ${bzr};then
    ((types += 1))
    selected_types+=('--bzr')
  fi
  if [ "${types}" -eq "0" ];then
    red_echo -n "Must select at least one repository type.  e.g. "
    yellow_echo "--git"
    STATUS=1
  elif [ "${types}" -gt "1" ];then
    red_echo -n "Multiple repository types not allowed.  Found:"
    for x in ${selected_types[@]};do
      yellow_echo -n " $x"
    done
    echo ""
    STATUS=1
  fi
  #test required project_name option
  if [ -z "${project_name}" ];then
    red_echo -n "Missing " 1>&2
    yellow_echo -n "--project-name" 1>&2
    red_echo " option." 1>&2
    STATUS=1
  fi
  #test required mirror option
  if [ -z "${mirror}" ];then
    red_echo -n "Missing " 1>&2
    yellow_echo -n "--mirror" 1>&2
    red_echo " option." 1>&2
    STATUS=1
  fi
  #test authors_file path for existence
  if [ ! -z "${authors_file}" -a ! -f "${authors_file}" ];then
    red_echo -n "Specified "
    yellow_echo -n "--authors-file"
    red_echo " does not exist!"
    STATUS=1
  fi
  #test ssl_verify environment variable (must be bool)
  if [ ! "${ssl_verify}" = "true" ] && [ ! "${ssl_verify}" = "false" ];then
    red_echo -n "ssl_verify="
    yellow_echo -n "${ssl_verify}"
    red_echo -n " is not a valid option for ssl_verify!  Must be "
    yellow_echo -n "true"
    red_echo -n " or "
    yellow_echo -n "false"
    red_echo "." 1>&2
    STATUS=1
  fi
  #test enable_colors environment variable (must be bool)
  if [ ! "${enable_colors}" = "true" ] && [ ! "${enable_colors}" = "false" ];then
    red_echo -n "enable_colors="
    yellow_echo -n "${enable_colors}"
    red_echo -n " is not a valid option for enable_colors!  Must be "
    yellow_echo -n "true"
    red_echo -n " or "
    yellow_echo -n "false"
    red_echo "." 1>&2
    STATUS=1
  fi
  #test issues_enabled environment variable (must be bool)
  if [ ! "${issues_enabled}" = "true" ] && [ ! "${issues_enabled}" = "false" ];then
    red_echo -n "issues_enabled="
    yellow_echo -n "${issues_enabled}"
    red_echo -n " is not a valid option for issues_enabled!  Must be "
    yellow_echo -n "true"
    red_echo -n " or "
    yellow_echo -n "false"
    red_echo "." 1>&2
    STATUS=1
  fi
  #test wall_enabled environment variable (must be bool)
  if [ ! "${wall_enabled}" = "true" ] && [ ! "${wall_enabled}" = "false" ];then
    red_echo -n "wall_enabled="
    yellow_echo -n "${wall_enabled}"
    red_echo -n " is not a valid option for wall_enabled!  Must be "
    yellow_echo -n "true"
    red_echo -n " or "
    yellow_echo -n "false"
    red_echo "." 1>&2
    STATUS=1
  fi
  #test wiki_enabled environment variable (must be bool)
  if [ ! "${wiki_enabled}" = "true" ] && [ ! "${wiki_enabled}" = "false" ];then
    red_echo -n "wiki_enabled="
    yellow_echo -n "${wiki_enabled}"
    red_echo -n " is not a valid option for wiki_enabled!  Must be "
    yellow_echo -n "true"
    red_echo -n " or "
    yellow_echo -n "false"
    red_echo "." 1>&2
    STATUS=1
  fi
  #test snippets_enabled environment variable (must be bool)
  if [ ! "${snippets_enabled}" = "true" ] && [ ! "${snippets_enabled}" = "false" ];then
    red_echo -n "snippets_enabled="
    yellow_echo -n "${snippets_enabled}"
    red_echo -n " is not a valid option for snippets_enabled!  Must be "
    yellow_echo -n "true"
    red_echo -n " or "
    yellow_echo -n "false"
    red_echo "." 1>&2
    STATUS=1
  fi
  #test public environment variable (must be bool)
  if [ ! "${public}" = "true" ] && [ ! "${public}" = "false" ];then
    red_echo -n "public="
    yellow_echo -n "${public}"
    red_echo -n " is not a valid option for public!  Must be "
    yellow_echo -n "true"
    red_echo -n " or "
    yellow_echo -n "false"
    red_echo "." 1>&2
    STATUS=1
  fi
  #test merge_requests_enabled environment variable (must be bool)
  if [ ! "${merge_requests_enabled}" = "true" ] && [ ! "${merge_requests_enabled}" = "false" ];then
    red_echo -n "merge_requests_enabled="
    yellow_echo -n "${merge_requests_enabled}"
    red_echo -n " is not a valid option for merge_requests_enabled!  Must be "
    yellow_echo -n "true"
    red_echo -n " or "
    yellow_echo -n "false"
    red_echo "." 1>&2
    STATUS=1
  fi
  return ${STATUS}
}

#
# Main execution
#

#Run a preflight check on options for compatibility.
if ! preflight;then
  echo "Command aborted due to previous errors." 1>&2
  exit 1
fi
#Check for namespace directory existence
if [ ! -e "${repo_dir}/${gitlab_namespace}" ];then
  mkdir -p "${repo_dir}/${gitlab_namespace}"
elif [ ! -d "${repo_dir}/${gitlab_namespace}" ];then
  red_echo "Error: \"${repo_dir}/${gitlab_namespace}\" exists but is not a directory." 1>&2
  exit 1
elif [ -d "${repo_dir}/${gitlab_namespace}/${project_name}" ] && ! ${force};then
  red_echo "Error: \"${repo_dir}/${gitlab_namespace}/${project_name}\" exists already.  Aborting command." 1>&2
  exit 1
fi
#Resolve the $authors_file path because of changing working directories
#/home/gitmirror/mirror-management/Mirrors/gitlab-mirrors/gitlab-mirrors/../authors_files/systems_authors_maps.txt
if [ ! -z "${authors_file}" ];then
  if ! echo "${authors_file}" | grep '^/' &> /dev/null;then
    authors_file="${PWD}/${authors_file}"
    authors_file="$(echo ${authors_file} | sed 's#/./#/#g')"
  fi
fi
cd "${git_mirrors_dir}"

#Set up project creation options based on config.sh to be passed to create manage_gitlab_project.py
CREATE_OPTS=""
if ${issues_enabled};then
  CREATE_OPTS="--issues ${CREATE_OPTS}"
fi
if ${wall_enabled};then
  CREATE_OPTS="--wall ${CREATE_OPTS}"
fi
if ${merge_requests_enabled};then
  CREATE_OPTS="--merge ${CREATE_OPTS}"
fi
if ${wiki_enabled};then
  CREATE_OPTS="--wiki ${CREATE_OPTS}"
fi
if ${snippets_enabled};then
  CREATE_OPTS="--snippets ${CREATE_OPTS}"
fi
if ${public};then
  CREATE_OPTS="--public ${CREATE_OPTS}"
fi

#Get the remote gitlab url for the specified project.
#If the project doesn't already exist in gitlab then create it.
if [ -z "${no_create}" ];then
  green_echo "Resolving gitlab remote." 1>&2
  if python lib/manage_gitlab_project.py --create --desc "Mirror of ${mirror}" ${CREATE_OPTS} "${project_name}" 1> /dev/null;then
    gitlab_remote=$(python lib/manage_gitlab_project.py --create --desc "Mirror of ${mirror}" ${CREATE_OPTS} "${project_name}")
  else
    red_echo "There was an unknown issue with manage_gitlab_project.py" 1>&2
    exit 1
  fi
  if [ -z "${gitlab_remote}" ];then
    red_echo "There was an unknown issue with manage_gitlab_project.py" 1>&2
    exit 1
  fi
else
  green_echo -n "Using remote: "
  echo "${no_create}"
  gitlab_remote="${no_create}"
fi
if ${git};then
  #create a mirror
  green_echo "Creating mirror from ${mirror}" 1>&2
  cd "${repo_dir}/${gitlab_namespace}"
  git clone --mirror "${mirror}" "${project_name}"
  cd "${project_name}"
  #add the gitlab remote
  green_echo "Adding gitlab remote to project." 1>&2
  git remote add gitlab "${gitlab_remote}"
  git config --add remote.gitlab.push '+refs/heads/*:refs/heads/*'
  git config --add remote.gitlab.push '+refs/tags/*:refs/tags/*'
  #Check the initial repository into gitlab
  green_echo "Checking the mirror into gitlab." 1>&2
  git fetch
  git remote prune origin
  git push gitlab
  green_echo "All done!" 1>&2
elif ${svn};then
  #create a mirror
  green_echo "Creating mirror from ${mirror}" 1>&2
  cd "${repo_dir}/${gitlab_namespace}"
  if [ ! -z "${authors_file}" ];then
    git svn clone "${mirror}" "${project_name}" ${git_svn_additional_options} --authors-file="${authors_file}"
  else
    git svn clone "${mirror}" "${project_name}" ${git_svn_additional_options}
  fi
  #add the gitlab remote
  green_echo "Adding gitlab remote to project." 1>&2
  cd "${project_name}"
  git remote add gitlab "${gitlab_remote}"
  git config --add remote.gitlab.push '+refs/heads/*:refs/heads/*'
  git config --add remote.gitlab.push '+refs/tags/*:refs/tags/*'
  #Check the initial repository into gitlab
  green_echo "Checking the mirror into gitlab." 1>&2
  git reset --hard
  git svn fetch
  cd .git
  git config --bool core.bare true
  git push gitlab
  git config --bool core.bare false
  green_echo "All done!" 1>&2
elif ${bzr};then
  #create a mirror
  green_echo "Creating mirror from ${mirror}" 1>&2
  cd "${repo_dir}/${gitlab_namespace}"
  git clone --mirror bzr::"${mirror}" "${project_name}"
  # cleaning repo
  cd "${project_name}"
  git gc --aggressive
  #add the gitlab remote
  git remote add gitlab "${gitlab_remote}"
  git config --add remote.gitlab.push '+refs/heads/*:refs/heads/*'
  git config --add remote.gitlab.push '+refs/tags/*:refs/tags/*'
  #Check the initial repository into gitlab
  green_echo "Checking the mirror into gitlab." 1>&2
  git push gitlab
  green_echo "All done!" 1>&2
else
  red_echo "Something has gone very wrong.  You should never see this message."
  exit 1
fi
