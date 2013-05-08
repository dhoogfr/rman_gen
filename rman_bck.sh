#!/bin/sh
#######################################################################################################
#                                                                                                     #
#  Author: D'Hooge Freek                                                                              #
#  Date:   18/11/2009                                                                                 #
#  Description: This rman backup script is to be used in combination with NetBackup.                  #
#               It uses the passed schedule name (via the $NB_ORA_PC_SCHED variable ) as a lookup key #
#               in the rman_bck_options.par parameter file to know for which database the backup      #
#               should be done and which backup options (mode, type, application schedule, ...)       #
#               have to be used.                                                                      #
#                                                                                                     #
#               Details of the possible parameters can be found in the rman_bck_options.par file      #
#                                                                                                     #
#               The location of the parameter file, the logfile or the name of the oracle software    #
#               owner can be set in the init routine                                                  #
#                                                                                                     #
#               Set the DEBUG flag to a number higher then 0 to log debug messages                    #
#               Currently the highest debug level is 2                                                #
#                                                                                                     #
#               IMPORTANT: the script uses oraenv to set the oracle environment, which means that     #
#                          all instances have to be listed in the oratab file with their correct home #
#                                                                                                     #
#                                                                                                     #
#  Last modified by: Freek D'Hooge                                                                    #
#  Date: 19/11/2009                                                                                   #
#  Description: Removed a wrong debug output to /tmp/tst                                              #
#                                                                                                     #
#  Last modified by: Freek D'Hooge                                                                    #
#  Date: 16/03/2010                                                                                   #
#  Description: Added the possibility to backup to disk and to backup backupsets to tape              #
#                                                                                                     #
#  Last modified by: Freek D'Hooge                                                                    #
#  Date: 17/02/2012                                                                                   #
#  Description: Added the path variable in the init sub to include the /usr/local/path                #
#               This solved the problem with oraenv when directly calling this script                 #
#               from within netbackup or cron (oraenv calls sethome, without providing the path)      #
#                                                                                                     #
#  Last modified by: Freek D'Hooge                                                                    #
#  Date: 23/05/2012                                                                                   #
#  Description: Fixed a problem with backups to disk ('DISK' != DISK)                                 #
#                                                                                                     #
#               Modified the execution of the command string (when executed by non root user), to use #
#               a variable (SH) containing the shell                                                  #
#                                                                                                     #
#               Added the possibility to use an external script that builds the rman command string   #
#               The specified script will be sourced into this script, so it has access to all        #
#               variables.                                                                            #
#               You can specify the external script by using the value EXTERNAL:<scriptname> for the  #
#               backup_mode field in the parameter file (note that you should specify the full path   #
#               to the script                                                                         #
#               The specified file should be readable by the user executing this script               #
#                                                                                                     #
#  Last modified by: Freek D'Hooge                                                                    #
#  Date: 03/06/2012                                                                                   #
#  Description: added the possibility to control the from address when emailing the logfile           #
#                                                                                                     #
#  Last modified by: Freek D'Hooge                                                                    #
#  Date: 08/05/2013                                                                                   #
#  Description: new changes will only be logged in the changelog anymore and not in this file itself  #
#                                                                                                     #
#######################################################################################################

DEBUG=0
DEBUGFILE=/tmp/rman_bck_`date '+%Y%m%d%H%M%S'`.debug


### Set the configuration variables
init ()
{ debugmsg 1 "Start of routine init"
  PATH=/usr/local/bin:$PATH ; export PATH
  PARFILE=/opt/oracle/backup/scripts/rman_bck.par
  LOGDIR=/opt/oracle/backup/logs/
  ORACLE_USER=grid
  GREP=/bin/grep
  ORAENV=/usr/local/bin/oraenv
  SH=/bin/sh
  SENDMAIL=/usr/sbin/sendmail
  ### set to Y if the logfile has to be mailed
  SENDLOGGING=Y
  ### if SENDLOGGING = Y, defines to where the rman logfile has to be mailed
  MAILTO='freek.dhooge@uptime.be'
  MAILFROM=oracle@mijntest.be

  debugmsg 2 "PATH         : $PATH"
  debugmsg 2 "PARFILE      : $PARFILE"
  debugmsg 2 "LOGDIR       : $LOGDIR"
  debugmsg 2 "ORACLE_USER  : $ORACLE_USER"
  debugmsg 2 "GREP         : $GREP"
  debugmsg 2 "ORAENV       : $ORAENV"

  debugmsg 1 "End of routine init"
}


### Output debug messages
debugmsg ()
{ DLEVEL=$1; shift
  DMESG=$@

  if [ $DEBUG -ge $DLEVEL ]
  then
    echo `date '+%Y%m%d%H%M%S'` ": $DMESG" >> $DEBUGFILE
  fi

}


### Determine which rman options should be used
### Get them via a lookup in the parameter file using the
### NB_ORA_PC_SCHED variable passed by NB
setBackupOptions ()
{ ### Find the line starting with the passed schedule name
  debugmsg 1 "Start of routine setBackupOptions"
  debugmsg 2 "  NB_ORA_PC_SCHED       : $NB_ORA_PC_SCHED"
  LINE=`$GREP -w "^$NB_ORA_PC_SCHED" $PARFILE`
  debugmsg 2 "  OPTIONS       : $LINE"
  ### Parse out the different option fields, trim leading and trailing spaces
  ORACLE_SID=`echo "$LINE" | cut -d';' -f2 | sed -e 's/^ *//' -e 's/ *$//'`
  TARGET_CONNECT_STR="connect target `echo "$LINE" | cut -d';' -f3 | sed -e 's/^ *//' -e 's/ *$//'`"
  CATALOG=`echo "$LINE" | cut -d';' -f4 | sed -e 's/^ *//' -e 's/ *$//'`
  BACKUP_MODE=`echo "$LINE" | cut -d';' -f5 | sed -e 's/^ *//' -e 's/ *$//'`
  BACKUP_TYPE=`echo "$LINE" | cut -d';' -f6 | sed -e 's/^ *//' -e 's/ *$//'`
  LEVEL=`echo "$LINE" | cut -d';' -f7 | sed -e 's/^ *//' -e 's/ *$//'`
  PARALLELISM=`echo "$LINE" | cut -d';' -f8 | sed -e 's/^ *//' -e 's/ *$//'`
  APPLICATION_SCHEDULE=`echo "$LINE" | cut -d';' -f9 | sed -e 's/^ *//' -e 's/ *$//'`
  DISK_DESTINATION=`echo "$LINE" | cut -d';' -f10 | sed -e 's/^ *//' -e 's/ *$//'`
  TAG=`echo "$LINE" | cut -d';' -f11 | sed -e 's/^ *//' -e 's/ *$//'`

  ### if the backup mode is referring to an external script then
  ### split the name of that script of the backup mode
  if [[ "$BACKUP_MODE" =~ ^EXTERNAL:.* ]]
  then
    EXTERNAL_SCRIPT=`echo $BACKUP_MODE | cut -d':' -f2`;
    BACKUP_MODE=EXTERNAL;
  fi


  debugmsg 2 "  ORACLE_SID            : $ORACLE_SID"
  debugmsg 2 "  TARGET_CONNECT_STR    : $TARGET_CONNECT_STR"
  debugmsg 2 "  CATALOG               : $CATALOG"
  debugmsg 2 "  BACKUP_MODE           : $BACKUP_MODE"
  debugmsg 2 "  EXTERNAL_SCRIPT       : $EXTERNAL_SCRIPT"
  debugmsg 2 "  BACKUP_TYPE           : $BACKUP_TYPE"
  debugmsg 2 "  LEVEL                 : $LEVEL"
  debugmsg 2 "  PARALLELISM           : $PARALLELISM"
  debugmsg 2 "  APPLICATION_SCHEDULE  : $APPLICATION_SCHEDULE"
  debugmsg 2 "  DISK_DESTINATION      : $DISK_DESTINATION"
  debugmsg 2 "  TAG                   : $TAG"

  ### Check if a catalog needs to be used
  if [ "$CATALOG" = "nocatalog" ]
  then
    CATALOG_CONNECT_STR=""
  else
    CATALOG_CONNECT_STR="connect catalog $CATALOG"
  fi

  ### Construct the backup options string and the backup tag string
  if [ "$BACKUP_MODE" = "EXTERNAL" ]
  then
    ### When using an external script the creation of the default tag and backup_options string is the responsibility of that external script,
    ### as there is no way for us to know which variables will be used and which not
    debugmsg 1 " Skipping construction of default tag and BACKUP_OPTIONS string due to external script";
  else
    if [ "$BACKUP_MODE" = "ARCH" ]
    then
      BACKUP_TAG=arch
    elif [ "$BACKUP_MODE" = "DISK_2_TAPE" ]
    then
      ### The backup tag of the original backup will be used
      BACKUP_TAG=""
    else
      ### If the backup_mode is different from ARCH, then the type should be added to the tag and options string
      if [ "$BACKUP_MODE" = "HOT" ]
      then
        BACKUP_TAG="HOT"
      elif [ "$BACKUP_MODE" = "COLD" ]
      then
        BACKUP_TAG="COLD"
      elif [ "$BACKUP_MODE" = "DISK_HOT" ]
      then
          BACKUP_TAG="HOT"
      fi
      
      if [ "$BACKUP_TYPE" = "FULL" ]
      then
        BACKUP_OPTIONS=full
        BACKUP_TAG=${BACKUP_TAG}"_FULL"
      elif [ "$BACKUP_TYPE" = "INC" ]
      then
        ### if the backup type is incremental, then the level should be added to the tag and options string
        BACKUP_OPTIONS="incremental level $LEVEL"
        BACKUP_TAG=${BACKUP_TAG}_INC_L${LEVEL}
      elif [ "$BACKUP_TYPE" = "CUM" ]
      then
        BACKUP_OPTIONS="incremental level $LEVEL cumulative"
        BACKUP_TAG=${BACKUP_TAG}_INC_L${LEVEL}_CUM
      fi
    fi
  fi
  
  ### Check if the default tag must be overridden by the user defined tag
  if [ "$TAG" != "" ]
  then
    BACKUP_TAG=$TAG
  fi

  debugmsg 2 "  BACKUP_TAG          : $BACKUP_TAG"
  debugmsg 2 "  BACKUP_OPTIONS      : $BACKUP_OPTIONS"
  debugmsg 1 "End of routine setBackupOptions"
}


### Set the Oracle variables
### The ORACLE_SID used in the oraenv script is set via the getOptions routine
setEnv ()
{ debugmsg 1 "Start of routine setEnv"
  CUSER=`id |cut -d"(" -f2 | cut -d ")" -f1`
  ORAENV_ASK=NO; export ORAENV_ASK
  . $ORAENV -s
  RMAN=$ORACLE_HOME/bin/rman
  debugmsg 2 "  ORACLE_HOME : $ORACLE_HOME"
  debugmsg 2 "  ORACLE_BASE : $ORACLE_BASE"
  debugmsg 2 "  TNS_ADMIN   : $TNS_ADMIN"
  debugmsg 2 "  RMAN        : $RMAN"
  debugmsg 1 "End of routine setBackupOptions"
}


### Initiate the rman logfile
initLogfile ()
{ debugmsg 1 "Start of routine initLogfile"
  LOGDATE=`date '+%Y%m%d%H%M%S'`
  if [ "$BACKUP_MODE" = "ARCH" ] || [ "$BACKUP_MODE" = "DISK_2_TAPE" ]
  then
    RMAN_LOG_FILE=${LOGDIR}/rman_${ORACLE_SID}_${LOGDATE}_${BACKUP_MODE}.log
  elif [ "$BACKUP_TYPE" = "FULL" ] || [ "$BACKUP_TYPE" = "CUM" ]
  then
    RMAN_LOG_FILE=${LOGDIR}/rman_${ORACLE_SID}_${LOGDATE}_${BACKUP_MODE}_${BACKUP_TYPE}.log
  elif [ "$BACKUP_TYPE" = "INC" ]
  then
    RMAN_LOG_FILE=${LOGDIR}/rman_${ORACLE_SID}_${LOGDATE}_${BACKUP_MODE}_${BACKUP_TYPE}L${LEVEL}.log
  else
    RMAN_LOG_FILE=${LOGDIR}/rman_${ORACLE_SID}_${LOGDATE}.log
  fi

  debugmsg 2 "  RMAN_LOG_FILE: $RMAN_LOG_FILE"

  echo >> $RMAN_LOG_FILE
  chmod 666 $RMAN_LOG_FILE
  debugmsg 1 "End of routine initLogfile"
}

### RMAN script used for hot backups to disk
bckDISK_HOT ()
{ debugmsg 1 "Start of routine bckDISK_HOT"
  CMD_STR="
    ORACLE_HOME=$ORACLE_HOME ; export ORACLE_HOME
    ORACLE_SID=$ORACLE_SID ; export ORACLE_SID
    LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH ; export LD_LIBRARY_PATH
    NLS_DATE_FORMAT='DD/MM/YYYY HH24:MI:SS' ; export NLS_DATE_FORMAT
    $RMAN msglog $RMAN_LOG_FILE append << EOF
      $TARGET_CONNECT_STR
      $CATALOG_CONNECT_STR
      set echo on
      ### Enable the controlfile autobackup
      ### This is not realy necessary when using an rman database catalog

      configure controlfile autobackup format for device type DISK to '$DISK_DESTINATION/%F';
      configure controlfile autobackup on;

      ### Set the channel configuration
      configure device type disk parallelism $PARALLELISM;
      configure default device type to disk;
      configure channel device type disk format '$DISK_DESTINATION/%U';

      ### Output the configuration
      show all;

      ### Do not perform any crosschecking, this will be done by a separate maintenance job

      ### Backup the database plus archivelogs
      ### Remove the archivelogs after the backup
      run
      { backup
          $BACKUP_OPTIONS
          tag $BACKUP_TAG
          database 
            include current controlfile
            plus archivelog delete all input
        ;
      }

      ### Clear the channel configuration
      configure device type disk clear;
      configure default device type clear;
      configure channel device type disk clear;

EOF
"
  debugmsg 2 "  CMD_STR: $CMD_STR"
  debugmsg 1 "End of routine bckDISK_HOT"
}

### RMAN script used to backup backupsets from disk to tape
bckDISK2TAPE ()
{ debugmsg 1 "Start of routine bckDISK2TAPE"
  CMD_STR="
    ORACLE_HOME=$ORACLE_HOME ; export ORACLE_HOME
    ORACLE_SID=$ORACLE_SID ; export ORACLE_SID
    LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH ; export LD_LIBRARY_PATH
    NLS_DATE_FORMAT='DD/MM/YYYY HH24:MI:SS' ; export NLS_DATE_FORMAT
    $RMAN msglog $RMAN_LOG_FILE append << EOF
      $TARGET_CONNECT_STR
      $CATALOG_CONNECT_STR
      set echo on
      ### Enable the controlfile autobackup

      configure controlfile autobackup format for device type 'SBT_TAPE' to '%F';
      configure controlfile autobackup on;

      ### Set the channel configuration
      configure device type sbt parallelism $PARALLELISM;
      configure default device type to sbt;
      configure channel device type sbt format '%U' PARMS='ENV=(NB_ORA_CLIENT=$NB_ORA_CLIENT, NB_ORA_POLICY=$NB_ORA_POLICY, NB_ORA_SCHED=$APPLICATION_SCHEDULE)';

      ### Set the backup optimization on.
      ### This will prevent that backupsets that are already backupped to disk to be backed up again.
      configure backup optimization on;
      
      ### Output the configuration
      show all;

      ### Do not perform any crosschecking, this will be done by a separate maintenance job
      
      ### backup the backupsets from disk that are not already backed up
      run
      { backup
          backupset all;
      }

      ### Clear the channel configuration
      configure device type sbt clear;
      configure default device type clear;
      configure channel device type sbt clear;

EOF
"
  debugmsg 2 "  CMD_STR: $CMD_STR"
  debugmsg 1 "End of routine bckDISK2TAPE"
}

### RMAN script used for hot backups
bckHOT ()
{ debugmsg 1 "Start of routine bckHOT"
  CMD_STR="
    ORACLE_HOME=$ORACLE_HOME ; export ORACLE_HOME
    ORACLE_SID=$ORACLE_SID ; export ORACLE_SID
    LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH ; export LD_LIBRARY_PATH
    NLS_DATE_FORMAT='DD/MM/YYYY HH24:MI:SS' ; export NLS_DATE_FORMAT
    $RMAN msglog $RMAN_LOG_FILE append << EOF
      $TARGET_CONNECT_STR
      $CATALOG_CONNECT_STR
      set echo on
      ### Enable the controlfile autobackup
      ### This is not realy necessary as we are using an rman database catalog

      configure controlfile autobackup format for device type 'SBT_TAPE' to '%F';
      configure controlfile autobackup on;

      ### Set the channel configuration
      configure device type sbt parallelism $PARALLELISM;
      configure default device type to sbt;
      configure channel device type sbt format '%U' PARMS='ENV=(NB_ORA_CLIENT=$NB_ORA_CLIENT, NB_ORA_POLICY=$NB_ORA_POLICY, NB_ORA_SCHED=$APPLICATION_SCHEDULE)';

      ### Output the configuration
      show all;

      ### Remove the expired backups from the recovery catalog
      ### Do this before taking the backup as this may influence the incremental level actually used
      allocate channel for maintenance device type 'SBT_TAPE';
      send 'NB_ORA_CLIENT=$NB_ORA_CLIENT';
      crosscheck backup;
      delete force noprompt expired backup;
      release channel;

      ### Backup the database plus archivelogs
      ### Remove the archivelogs after the backup
      run
      { backup
          $BACKUP_OPTIONS
          tag $BACKUP_TAG
          database 
            include current controlfile
            plus archivelog delete all input
        ;
      }

      ### Clear the channel configuration
      configure device type sbt clear;
      configure default device type clear;
      configure channel device type sbt clear;

EOF
"
  debugmsg 2 "  CMD_STR: $CMD_STR"
  debugmsg 1 "End of routine bckHOT"
}


### RMAN script used for offline backups
bckCOLD ()
{ debugmsg 1 "Start of routine bckCOLD"
  CMD_STR="
    ORACLE_HOME=$ORACLE_HOME ; export ORACLE_HOME
    ORACLE_SID=$ORACLE_SID ; export ORACLE_SID
    LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH ; export LD_LIBRARY_PATH
    NLS_DATE_FORMAT='DD/MM/YYYY HH24:MI:SS' ; export NLS_DATE_FORMAT
    $RMAN msglog $RMAN_LOG_FILE append << EOF
      $TARGET_CONNECT_STR
      $CATALOG_CONNECT_STR

      set echo on

      ### Enable the controlfile autobackup
      ### This is not realy necessary as we are using an rman database catalog
      configure controlfile autobackup format for device type 'SBT_TAPE' to '%F';
      configure controlfile autobackup on;

      ### Set the channel configuration
      configure device type sbt parallelism $PARALLELISM;
      configure default device type to sbt;
      configure channel device type sbt format '%U' PARMS='ENV=(NB_ORA_CLIENT=$NB_ORA_CLIENT, NB_ORA_POLICY=$NB_ORA_POLICY, NB_ORA_SCHED=$APPLICATION_SCHEDULE)';

      ### Output the configuration
      show all;

      ### Remove the expired backups from the recovery catalog
      ### Do this before taking the backup as this may influence the incremental level actually used
      allocate channel for maintenance device type 'SBT_TAPE';
      send 'NB_ORA_CLIENT=$NB_ORA_CLIENT';
      crosscheck backup;
      delete force noprompt expired backup;
      release channel;

      ### Restart the DB in mount mode
      shutdown immediate;
      startup mount;

      ### Backup the database (do not backup any archivelogs)
      run
      { backup
          $BACKUP_OPTIONS
          tag $BACKUP_TAG
          database
            include current controlfile
        ;
      }

      ### Open the database again
      sql 'alter database open';

      ### Clear the channel configuration
      configure device type sbt clear;
      configure default device type clear;
      configure channel device type sbt clear;

EOF
"
  debugmsg 2 "  CMD_STR: $CMD_STR"
  debugmsg 1 "End of routine bckCOLD"
}


### RMAN script used for archivelog backups
bckARCH ()
{ debugmsg 1 "Start of routine bckARCH"
  CMD_STR="
    ORACLE_HOME=$ORACLE_HOME ; export ORACLE_HOME
    ORACLE_SID=$ORACLE_SID ; export ORACLE_SID
    LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH ; export LD_LIBRARY_PATH
    NLS_DATE_FORMAT='DD/MM/YYYY HH24:MI:SS' ; export NLS_DATE_FORMAT
    $RMAN msglog $RMAN_LOG_FILE append << EOF
      $TARGET_CONNECT_STR
      $CATALOG_CONNECT_STR

      set echo on

      ### Set the channel configuration
      configure device type sbt parallelism $PARALLELISM;
      configure default device type to sbt;
      configure channel device type sbt format '%U' PARMS='ENV=(NB_ORA_CLIENT=$NB_ORA_CLIENT, NB_ORA_POLICY=$NB_ORA_POLICY, NB_ORA_SCHED=$APPLICATION_SCHEDULE)';

      ### Output the configuration
      show all;

      ### Backup the archivelogs, delete them from disk afterwards
      run
      { backup
          tag $BACKUP_TAG
          archivelog all delete all input;
      }

      ### Clear the channel configuration
      configure device type sbt clear;
      configure default device type clear;
      configure channel device type sbt clear;

EOF
"
  debugmsg 2 "  CMD_STR: $CMD_STR"
  debugmsg 1 "End of routine bckCOLD"
}


### Print the header part of the logfile
printHeader ()
{ debugmsg 1 "Start of routine printHeader"
  ### Log the start of this script
  echo Script $0 >> $RMAN_LOG_FILE
  echo ==== started on `date` ==== >> $RMAN_LOG_FILE
  echo >> $RMAN_LOG_FILE

  ### Log the variables set by this script
  echo >> $RMAN_LOG_FILE
  echo   "RMAN       : $RMAN" >> $RMAN_LOG_FILE
  echo   "ORACLE_SID : $ORACLE_SID" >> $RMAN_LOG_FILE
  echo   "ORACLE_USER: $ORACLE_USER" >> $RMAN_LOG_FILE
  echo   "ORACLE_HOME: $ORACLE_HOME" >> $RMAN_LOG_FILE
  echo >> $RMAN_LOG_FILE
  echo   "SCHEDULE            : $NB_ORA_PC_SCHED" >> $RMAN_LOG_FILE
  echo   "APPLICATION SCHEDULE: $APPLICATION_SCHEDULE" >> $RMAN_LOG_FILE
  echo   "BACKUP MODE         : $BACKUP_MODE" >> $RMAN_LOG_FILE
  echo   "EXTERNAL_SCRIPT     : $EXTERNAL_SCRIPT" >> $RMAN_LOG_FILE
  echo   "BACKUP TYPE         : $BACKUP_TYPE" >> $RMAN_LOG_FILE
  echo   "LEVEL               : $LEVEL" >> $RMAN_LOG_FILE
  echo   "PARALLELISM         : $PARALLELISM" >> $RMAN_LOG_FILE
  echo   "TAG                 : $BACKUP_TAG" >> $RMAN_LOG_FILE
  echo >> $RMAN_LOG_FILE
  debugmsg 1 "End of routine printHeader"
}


### Print the footer part of the logfile
printFooter ()
{ debugmsg 1 "Start of routine printFooter"
  debugmsg 2 "  RSTAT: $RSTAT"
  if [ "$RSTAT" = "0" ]
  then
    LOGMSG="ended successfully"
  else
    LOGMSG="ended in error"
  fi

  echo >> $RMAN_LOG_FILE
  echo Script $0 >> $RMAN_LOG_FILE
  echo ==== $LOGMSG on `date` ==== >> $RMAN_LOG_FILE
  echo >> $RMAN_LOG_FILE
  debugmsg 1 "End of routine printFooter"
}


### Determine which command string should be created and execute it
### Trap the exit code for further use
runBackup ()
{ debugmsg 1 "Start of routine runBackup"
  ### Create the correct command string
  case $BACKUP_MODE in
    "HOT")
      debugmsg 2 "  HOT backup mode selected"
      bckHOT
    ;;
    "COLD")
      debugmsg 2 "  COLD backup mode selected"
      bckCOLD
    ;;
    "ARCH")
      debugmsg 2 "  ARCH backup mode selected"
      bckARCH
    ;;
    "DISK_HOT")
      debugmsg 2 "  HOT backup to disk mode selected"
      bckDISK_HOT
    ;;
    "DISK_2_TAPE")
      debugmsg 2 "  Backup backupsets to tape mode selected"
      bckDISK2TAPE
    ;;
    "EXTERNAL")
      debugmsg 2 "  External script selected"
      if [ -r $EXTERNAL_SCRIPT ]
      then
        source $EXTERNAL_SCRIPT
      else
        debugmsg 2 "  file $EXTERNAL_SCRIPT does not exist or is not readable"
        echo "file $EXTERNAL_SCRIPT does not exist or is not readable" >> $RMAN_LOG_FILE
        exit 1
      fi
    ;;
    *)
      debugmsg 2 "  Not a valid backup mode"
      echo "Not a valid backup mode" >> $RMAN_LOG_FILE
      exit 1
    ;;
  esac

  ### Initiate the command string
  if [ "$CUSER" = "root" ]
  then
    debugmsg 2 "  Switching to user $ORACLE_USER to run the backup"
    su - $ORACLE_USER -c "$CMD_STR" >> $RMAN_LOG_FILE
    RSTAT=$?
    debugmsg 2 "  Resultcode: $RSTAT"
  else
    debugmsg 2 "Running the backup as user $CUSER"
    $SH -c "$CMD_STR" >> $RMAN_LOG_FILE
    RSTAT=$?
    debugmsg 2 "  Resultcode: $RSTAT"
  fi
  debugmsg 1 "End of routine runBackup"
}

### Mail the logfile
sendLog ()
{ debugmsg 1 "Start of routine sendlog"
  ### check if the logfile has to be mailed
  if [ "$SENDLOGGING" = "Y" ]
  then
    debugmsg 1 "sendlogging enabled"
    ### construct the subject of the mail, make a clear distinction between successfull backups and failed ones
    if [ "$RSTAT" = "0" ]
    then
      debugmsg 2 "constructing mail subject for succcessfull backup"
      MAILSUBJECT="backup $ORACLE_SID - `hostname` - `date`"
    else
      debugmsg 2 "constructing mail subject for failed backup"
      MAILSUBJECT="FAILED backup $ORACLE_SID - `hostname` - `date`"
    fi
    # if no from address is explicitly set, then use the current username and hostname of the server
    if [ "$MAILFROM" = "" ]
    then
      MAILFROM="${USER}@${HOSTNAME}"
    fi
    ### send the mail
    debugmsg 2 "MAILSUBJECT: $MAILSUBJECT"
    debugmsg 2 "MAILTO: $MAILTO"
    debugmsg 2 "RMAN LOG FILE: $RMAN_LOG_FILE"
#    mail -s "$MAILSUBJECT" $MAILTO < $RMAN_LOG_FILE
    ${SENDMAIL} -f ${MAILFROM} -t <<EOF
from: ${MAILFROM}
to: ${MAILTO}
subject: ${MAILSUBJECT}
`cat ${RMAN_LOG_FILE}`

EOF
 fi 
 debugmsg 1 "End of routing sendlog"
}

### Main execution routine
main ()
{ debugmsg 1 "Start of routine main"
  ### Initialize this script
  init
  ### Get the backup options to be used from the parameter file and set the necessary variables
  setBackupOptions
  ### Set the oracle environment variables
  setEnv
  ### Initiate the logfile
  initLogfile
  ### Set the header in the logfile
  printHeader
  ### Construct and run the RMAN command string
  ### Output will be logged in the logfile
  runBackup
  ### Print the footer in the logfile
  printFooter
  ### Send the logfile
  sendLog
  ### Exit with the rman result code, so NB knows if the backup succeeded or not
  debugmsg 2 "End of routine main"
  exit $RSTAT
}

main

