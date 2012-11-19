#!/bin/bash

# script is developed for file-based backup systems so we wont compress because it make impossible to diff,
# and compression should be handled by backup software as it do with other files too.

# Application: file-ize the mysql data optimized for backing up via backup software
# TODO: if a database no longer exists, remove the dump file.
# TODO: if a diff bigger than the dump, replace the dump with the new one and write a new chksum.

. ./CxMySQL.cfg

if [ ! -d ${dumpdir} ]; then
    mkdir -pv ${dumpdir}
    sleep 5
fi

function usage {
    echo "usage: ${0} <dump/dump_all/dump_diff/dump_diff_all/restore> [database]"
}

function dump_db_create {
    DB=${1}
    echo "drop database IF EXISTS ${DB};">${dumpdir}/${DB}.create.sql
    echo "show create database ${DB}" | $my | grep -vE '^Database' | sed "s/^${DB}//g" >>${dumpdir}/${DB}.create.sql
    echo ";">>${dumpdir}/${DB}.create.sql
    echo "use ${DB};" >>${dumpdir}/${DB}.create.sql
}

function checksum_table {
    DB=${1}
    TABLE=${2}
    echo "checksum table ${TABLE}" | $my ${DB} | grep -vE '^Table' | awk '{print $2}'
}

function dump_table {
    DB=${1}
    TABLE=${2}
    mysqldump --single-transaction --skip-comments --skip-extended-insert -u ${dbuser} -p${dbpass} --databases "$DB" --tables "$TABLE" | sed 's/--.*//g' | sed '/^$/d'
}

function dump_db {
    DB=${1}
    if [ ! -d ${dumpdir}/${DB} ]; then
	mkdir ${dumpdir}/${DB}
    fi

    dump_db_create ${DB} # show create database >db.create.sql

    # get tables #
    echo "show tables" | $my ${DB} | grep -vE '^Tables_in' | while read TABLE; do
	if [ -f ${dumpdir}/${DB}/${TABLE}.sql ]; then
	    echo -n " [ removing old data ] "
	    rm -f ${dumpdir}/${DB}/${TABLE}.sql
	    rm -f ${dumpdir}/${DB}/${TABLE}.diff
	    rm -f ${dumpdir}/${DB}/${TABLE}.chksum
	fi
	echo "proccessing table: ${TABLE}"

	dump_table ${DB} ${TABLE} >${dumpdir}/${DB}/${TABLE}.sql
	CHKSUM=`checksum_table ${DB} ${TABLE}`
	echo ${CHKSUM}>${dumpdir}/${DB}/${TABLE}.chksum

	
    done
}

function dump_all {
    echo "show databases" | $my | grep -vE '^Database$' | while read DB; do
	echo "processing database: ${DB}"
	dump_db ${DB}
    done
}

function dump_diff {
    DB=${1}
    if [ ! -d ${dumpdir}/${DB} ]; then
	mkdir ${dumpdir}/${DB}
    fi

    dump_db_create ${DB} # show create database >db.create.sql
    
    # get tables #
    echo "show tables" | $my ${DB} | grep -vE '^Tables_in' | while read TABLE; do
	if [ -f ${dumpdir}/${DB}/${TABLE}.chksum ]; then

    	    LVSUM=`checksum_table ${DB} ${TABLE}`
    	    SASUM=`cat ${dumpdir}/${DB}/${TABLE}.chksum` 
#    	    echo "LVSUM: [${LVSUM}]"
#    	    echo "SASUM: [${SASUM}]"
	    if [ ${SASUM} -ne ${LVSUM} ]; then
		echo -n ' [+] '
    		dump_table ${DB} ${TABLE}>${dumpdir}/tmp.sql
    		diff -u ${dumpdir}/${DB}/${TABLE}.sql  ${dumpdir}/tmp.sql>${dumpdir}/${DB}/${TABLE}.diff
    		rm -f ${dumpdir}/tmp.sql
    		echo "${LVSUM}">${dumpdir}/${DB}/${TABLE}.chksum
    	    else
    		echo -n ' [-] '
    	    fi
	    echo  "comparing: ${DB} :: ${TABLE}"
    	else
    	    echo "cannot compare ${DB} :: ${TABLE}, no checksum found. re-dumping table and writing checksum"
	    dump_table ${DB} ${TABLE}
    	fi

    done
}

function dump_diff_all {
    echo "show databases" | $my | grep -vE '^Database$' | while read DB; do
	echo "dump diffing: ${DB}"
	dump_diff ${DB}
    done
}

function restore_db {
    DB=${1}
    RFILE=${dumpdir}/${DB}.restore.sql
    echo "building restore file for DB:${DB}"

    echo -n "database creation"
    cat ${dumpdir}/${DB}.create.sql >${RFILE}
    echo " [done] "
    
    echo -n "searching for patches.. "
    NEEDTOPATCH=0
    find ${dumpdir}/${DB} | grep -E '.diff$' | while read NPATCH; do
	echo " [needs patching: ${NPATCH} ]"
	NEEDTOPATCH=1
    done
    if [ ${NEEDTOPATCH} -eq 1 ]; then
	echo " [tables needs patching. do it and delete the .diff files] "
	exit # TODO: we should do that :)
    fi
    
    echo -n "inserting table data.. "
    find ${dumpdir}/${DB} | grep -E '.sql$' | while read SQLFILE; do
	cat ${SQLFILE}>>${RFILE}
    done
    echo " [done] "
    echo
    echo "${RFILE} is ready to apply"
}

function restore_all {
    echo "show databases" | $my | grep -vE '^Database$' | while read DB; do
	restore_db ${DB}
    done
    echo "i made .restore.sql files to ${dumpdir}, feel free to cat *.restore.sql| mysql .. blah"
}

case "${1}" in
    dump_all)
	dump_all
    ;;
    dump)
	if [ ${#2} -lt 1 ]; then
	    echo "please specify database name for the dump command"
	    exit
	fi
	dump_db ${2}
    ;;
    dump_diff)
	dump_diff ${2}
    ;;
    dump_diff_all)
	dump_diff_all
    ;;
    restore)
	restore_db ${2}
    ;;
    restore_all)
	restore_all
	
    ;;
    *)
    usage
esac
