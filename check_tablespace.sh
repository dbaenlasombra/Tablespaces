#!/bin/bash
# DSM


. /home/oracle/.bashrc

UMBRAL=${1}
TODAY=$(date '+%Y-%m-%d %H:%M:%S')

lanza_sqlplus() {
    sqlplus -s ${VUSER}/${VPASS}@${LOCAL_SID} <<EOF
    set lines 200 pages 9000
    set termout off
    set heading off
    ${SQL}
    EXIT;
EOF
}

getInfo_Tablespace() {
    sqlplus -s ${VUSER}/${VPASS}@${LOCAL_SID} <<EOF
     set lines 200 pages 9000
     set termout off
     set heading off
     set feedback off;
     spool INFO_TABLESPACE.log
     Select 'Tablespace '||"Name"||' Ocupado: '||Trunc("(Used) %",2)||'%' Info, "Name" Tablespace_Nane
      From  (
      Select d.Status "Status",
         d.Tablespace_Name "Name",
         To_Char(Nvl(a.Bytes / 1024 / 1024 / 1024, 0), '99,999,990.90') "Size (GB)",
         To_Char(Nvl(a.Bytes - Nvl(f.Bytes, 0), 0) / 1024 / 1024 / 1024,
                 '99999999.99') "Used (GB)",
         To_Char(Nvl(f.Bytes / 1024 / 1024 / 1024, 0), '99,999,990.90') "Free (GB)",
         Nvl((a.Bytes - Nvl(f.Bytes, 0)) / a.Bytes * 100, 0) "(Used) %"
       From Sys.Dba_Tablespaces d,
         (
         Select Pp.Name Tablespace_Name, Sum(Bytes) Bytes
          From V\$datafile Rr, V\$tablespace Pp
          Where Rr.Ts# = Pp.Ts#
           And ( Case When REGEXP_LIKE ( Substr(Pp.Name,-4), '^[[:digit:]]+$') Then 'N' Else 'S' End )  = 'N'
           And Instr( Substr(Pp.Name,-4), Extract(Year From Sysdate ) ) != 0
         Group By Pp.Name
        Union All
        Select Pp.Name Tablespace_Name, Sum(Bytes) Bytes
          From V\$datafile Rr, V\$tablespace Pp
         Where Rr.Ts# = Pp.Ts#
           And ( Case When REGEXP_LIKE ( Substr(Pp.Name,-4), '^[[:digit:]]+$') Then 'N' Else 'S' End )  = 'S'
         Group By Pp.Name
          ) a,
         (Select Tablespace_Name, Sum(Bytes) Bytes
            From Dba_Free_Space
           Group By Tablespace_Name) f
      Where d.Tablespace_Name = a.Tablespace_Name(+)
        And d.Tablespace_Name = f.Tablespace_Name(+)
        And Not (d.Extent_Management Like 'LOCAL' And d.Contents Like 'TEMPORARY')
     ) Where "(Used) %" >= ${UMBRAL} And Instr("Name",'SYS') =  0 And Instr("Name",'UNDOTBS1') = 0;
    set heading on;
    set feedback on;
    spool off;
    exit;
EOF
}

   getInfo_Tablespace

   LINEAS=`cat INFO_TABLESPACE.log`

   if [[ "$LINEAS" ]]
   then
     while IFS='' read -r line
     do
      set __ $line
      TABLESPACE=${6}
      if [[ "${TABLESPACE}" ]]
      then

      SQL=$(cat <<EOF
     Select Trunc(a.Bytes / (1024 * 1024 * 1024),2)
       From
         (
         Select Sum(Bytes) Bytes
          From V\$datafile Rr, V\$tablespace Pp
          Where Rr.Ts# = Pp.Ts#
           And Pp.Name = '${TABLESPACE}'
         Group By Pp.Name
          ) a
         ;
EOF
   )

      set __ $(lanza_sqlplus)
      ORIGINAL=${2}

      SQL=$(cat <<EOF
       Select Name, Ceil((BYTES + (5*(1024*1024*1024)))/1024/1024) Size_Mb
        From (
         Select r.FILE#, r.NAME , BYTES
          From v\$datafile r, v\$Tablespace z
         Where z.name = '${TABLESPACE}'
           And z.ts# = r.TS#
         Order By CREATION_TIME Desc
             )
        Where Rownum = 1;
EOF
    )

     set __ $(lanza_sqlplus)

     DATAFILE=${2}
     TAMANYO=${3}

     if [[ "${DATAFILE}" ]]
     then
     echo ${2}
     SQL=$(cat << EOF
     begin
      execute immediate 'ALTER DATABASE DATAFILE ''${DATAFILE}'' RESIZE  ${TAMANYO}M';
     end;
     /
EOF
)
     ISSUE=`echo $(lanza_sqlplus)`

SQL=$(cat <<EOF
 Select Trunc(a.Bytes / (1024 * 1024 * 1024),2)
       From
         (
         Select Sum(Bytes) Bytes
          From V\$datafile Rr, V\$tablespace Pp
          Where Rr.Ts# = Pp.Ts#
           And Pp.Name = '${TABLESPACE}'
         Group By Pp.Name
          ) a
         ;
EOF
   )

      set __ $(lanza_sqlplus)
      FINAL=${2}

     printf "Mantenimiento=${TABLESPACE}\nSize Ant=${ORIGINAL}\nAct=${FINAL}\nissue=${ISSUE}"  | mailx -s "[XXXX] Mantenimiento Tablespace ${TABLESPACE}  with more ${UMBRAL} - ${TODAY}." ${EMAIL}
     fi
     fi
     done <  INFO_TABLESPACE.log
   fi
