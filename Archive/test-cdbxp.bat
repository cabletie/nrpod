echo off
rem CDBurnerXP test run
rem "C:/Program Files/CDBurnerXP/cdbxpcmd.exe" --load -device:0
rem "D:/Users/peter/Documents/bin/CreateCD.exe" -info -recorder:e
rem "C:/Program Files/CDBurnerXP/cdbxpcmd.exe" --burn-iso:test_for_scripting.iso -dao -close -eject -device:0 -folder:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\wav" -name:"North Ringwood Uniting Church"

rem burn iso of audio from whole folder
rem "C:/Program Files/CDBurnerXP/cdbxpcmd.exe" --burn-audio -iso:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\test_for_scripting.iso" -folder:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\wav"

rem burn iso of audio from individual files
rem "C:/Program Files/CDBurnerXP/cdbxpcmd.exe" --burn-audio -iso:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\test_for_scripting.iso" -file:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\wav\test_for_scripting-1.wav" -file:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\wav\test_for_scripting-2.wav" -file:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\wav\test_for_scripting-3.wav" -file:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\wav\test_for_scripting-4.wav" 

rem burn audio from individual files
"C:/Program Files/CDBurnerXP/cdbxpcmd.exe" --burn-audio  -file:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\wav\test_for_scripting-1.wav" -file:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\wav\test_for_scripting-2.wav" -file:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\wav\test_for_scripting-3.wav" -file:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\wav\test_for_scripting-4.wav" 

Rem burn actual disk from files in wav directory
rem "C:/Program Files/CDBurnerXP/cdbxpcmd.exe" --burn-audio -dao -close -eject -device:0 -iso:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\test_for_scripting.iso" -folder:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\wav"

Rem burn audio from axp file
rem "C:/Program Files/CDBurnerXP/cdbxpcmd.exe" -layout:"D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\test_for_scripting.axp"

Rem start cdburnerxp with axp file
rem "C:/Program Files/CDBurnerXP/cdbxpp.exe" "D:\Users\peter\Documents\Audacity\service_recordings\test_for_scripting\test_for_scripting.axp"
