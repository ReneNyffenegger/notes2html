@pushd test_notes
@..\notes2html.pl

@cd ..\test_out
@for  %%i in (*.html) do @fc %%i ..\test_expected\%%i  | findstr /c:"****"

@popd
