#!/bin/bash
_curdir="$(realpath "$(dirname "${0}")")"
_config="${_curdir}/config"
_outdir="${_curdir}/out"
_wget='wget --no-verbose --continue --output-document="%s" "%s"'
function _error(){
	local err="${1}"
	shift
	echo "${@}" >&2
	exit "${err}"
}
function _gen_wget(){ printf "${_wget}\n" "${1}" "${2}"; }
function _call_wget(){ eval "$(_gen_wget "${1}" "${2}")"; }
function _download(){
	local i _num _tempdir _temp _srv _out _db _repo _arg
	local _CSIZE _NAME _FILENAME _SHA256SUM _from _dest
	_repo="${1}"
	_out="${_outdir}/${repo}"
	_temp="$(mktemp --tmpdir download_list_XXXXXX)"
	_temphash="$(mktemp --tmpdir hash_list_XXXXXX)"
	_tempdir="$(mktemp --tmpdir --directory extract_database_XXXXXX)"
	_srv="$(_geturl "${1}")"
	_db="${_out}/${_repo}.db"
	_dburl="${_srv}/${_repo}.db"
	[ -d "${_out}" ]||mkdir -p "${_out}"
	[ -d "${_out}" ]||_error 1 "failed to create repo output folder ${_out}"
	[ -f "${_temp}" ]||_error 1 "failed to mktemp download_list"
	[ -f "${_temphash}" ]||_error 1 "failed to mktemp hash_list"
	[ -d "${_tempdir}" ]||_error 1 "failed to mktemp -d extract_database"
	_call_wget "${_db}" "${_dburl}"||_error "${?}" "failed to download database ${_dburl}"
	_call_wget "${_db}.sig" "${_dburl}.sig"
	tar --extract --directory="${_tempdir}" --file="${_db}"||_error "${?}" "failed to extract database ${_db}"
	echo "processing database ${_db} ..."
	true >"${_temp}"
	i=0
	_num=0
	for dir in "${_tempdir}/"*
	do	[ -d "${dir}" ]||continue
		[ -f "${dir}/desc" ]||continue
		i=$((i+1))
		_arg='/%FILENAME%/{getline;print "_FILENAME="$0};'
		_arg+='/%NAME%/{getline;print "_NAME="$0};'
		_arg+='/%SHA256SUM%/{getline;print "_SHA256SUM="$0};'
		_arg+='/%CSIZE%/{getline;print "_CSIZE="$0};'
		eval "$(awk "${_arg}" "${dir}/desc")"||_error "$?" "cannot read database item ${dir}/desc"
		printf '\rprocessing package %s\e[K\r' "${_NAME}"
		[ -z "${_NAME}" ]&&_error 1 "cannot get NAME from database"
		[ -z "${_NAME}" ]&&_error 1 "cannot get FILENAME from database"
		[ -z "${_SHA256SUM}" ]&&_error 1 "cannot get SHA256SUM from database"
		_from="${_srv}/${_FILENAME}"
		_dest="${_out}/${_FILENAME}"
		if [ "$(stat -Lc '%s' "${_dest}" 2>/dev/null)" != "${_CSIZE}" ]
		then	_num=$((_num+1))
			_gen_wget "${_dest}" "${_from}" >>"${_temp}"
			_gen_wget "${_dest}.sig" "${_from}.sig" >>"${_temp}"
		fi
		echo "${_SHA256SUM} ${_dest}" >>"${_temphash}"
		unset _NAME _FILENAME _SHA256SUM
		rm -f "${dir}/desc"
		rmdir "${dir}"
	done
	printf '\r%s done.\e[K\n' "${_repo}"
	rmdir "${_tempdir}"
	printf '%d of %d need download\n' "${_num}" "${i}"
	echo "start download packages"
	if type parallel &>/dev/null
	then parallel -j "${threads}" <"${_temp}"
	else	echo "WARNING: parallel not found"
		while read -r cmd;do "${cmd}";done<"${_temp}"
	fi
	rm -f "${_temp}"
	echo "download ${_repo} done."
	echo "start sha256sum packages"
	if sha256sum --quiet --check "${_temphash}"
	then echo "sha256sum ${_repo} done."
	else _error 1 "sha256sum ${_repo} failed!"
	fi
	rm -f "${_temphash}"
}
function _geturl(){
	local _url
	_url="$(eval echo "\${url_${1//_/-}}")"
	[ -z "${_url}" ]&&_error 1 "repo ${1} no url"
	echo "${_url}"
}
function _help(){
	echo "Usage: ./download.sh"
	echo
	echo "Download archlinux packages."
	echo
	echo "Options: "
	echo "	--config CONFIG, -c CONFIG: set config file path."
	echo "	--threads N, -t N:          set download parallel threads."
	echo "	--jobs N, -j N:             set download parallel threads."
	echo "	--output-dir PATH, -O PATH: set output folder path."
	echo "	--command CMD,-C CMD:       set download command."
	echo "	--help, -h:                 show this help."
	echo
	echo "MainPage: https://github.com/BigfootACA/archiso-offline"
	exit "${1}"
}
OPTS="$(getopt -o ht:j:c:O:C: -l config:,help,output-dir:,jobs:,threads:,command: -n 'download.sh' -- "$@")"||exit 1
eval set -- "${OPTS}"
while true
do	case "${1}" in
		-O|--output-dir)_outdir="${2}";shift 2;;
		-c|--config)_config="${2}";shift 2;;
		-t|--threads|-j|--jobs)threads="${2}";shift 2;;
		-C|--command)_wget="${2}";shift 2;;
		-h|--help)_help 0;shift;;
		--)shift;break;;
		*)_help 1;;
        esac
done
[ -f "${_config}" ]||_error 1 "config file ${_config} not found"
_config="$(realpath "${_config}")"
_outdir="$(realpath "${_outdir}")"
source "${_config}"
[ -z "${threads}" ]&&threads="$(nproc)"
[ -z "${repos}" ]&&_error 1 "no repos defined"
for repo in "${repos[@]}";do _geturl "${repo}" >/dev/null;done
[ -d "${_outdir}" ]||mkdir -p "${_outdir}"
[ -d "${_outdir}" ]||_error 1 "failed to create output folder ${_outdir}"
for repo in "${repos[@]}";do _download "${repo}";done
