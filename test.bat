@del test_out\*.html

notes2html.pl  --debug test_notes test_out

@pushd test_expected
@for  %%i in (*.html) do @fc %%i ..\test_out\%%i | findstr /c:"***"

@popd
