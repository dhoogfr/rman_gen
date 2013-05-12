rman_gen
========

Generate and execute an Oracle rman script based upon the schedule name passed via netbackup (or manually set in the environment) and values found in a parameter file.
See the example parameter file for which options are possible.

When using netbackup, set the backup_selection to the rman_bck.sh script.
When running the script directly use the rman_bck_to_disk.sh script and pass the lookup "schedule name" as parameter.

Aside from the buildin rman scenario's, it is possible to setup a separate file containing your own rman commands and specify that script in the backup_mode field of the parameter script by using "EXTERNAL:<full path to the script>"