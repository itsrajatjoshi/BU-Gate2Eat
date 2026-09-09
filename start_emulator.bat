@echo off
set "JAVA_HOME=C:\Program Files\Java\latest\jdk-25"
set "PATH=C:\Program Files\Java\latest\jdk-25\bin;%PATH%"
call npx.cmd --yes firebase-tools emulators:start --only storage
