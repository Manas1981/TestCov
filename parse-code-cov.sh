#!/bin/sh -e

# frame "body & LCOV report"
lynx --dump code-cov/index.html | grep 'LCOV' >> out.txt

sed -i.bak -e '2d' out.txt

sed -i.bak 's/^.*LCOV/{\"body\":\"LCOV/' out.txt

tr -d "\n\r" < out.txt > out1.txt

echo -n "\n" >> out1.txt

# frame "View:"
lynx --dump code-cov/index.html | grep 'Current view' > out2.txt

sed -i.bak 's/^.*Hit/View:      Hit/' out2.txt

cat out2.txt >> out1.txt

tr -d "\n\r" < out1.txt > out.txt
echo -n "\n" >> out.txt

# frame "Lines:"
lynx --dump code-cov/index.html | grep 'Lines' > out2.txt

sed -i.bak 's/^.*Lines/Lines/' out2.txt

cat out2.txt >> out.txt

tr -d "\n\r" < out.txt > out1.txt
echo -n "\n" >> out1.txt

# frame "Functions:"
lynx --dump code-cov/index.html | grep 'Functions' > out2.txt
sed -i.bak -e '2d' out2.txt
sed -i.bak 's/^.*Functions/Functions/' out2.txt

cat out2.txt >> out1.txt
tr -d "\n\r" < out1.txt > out.txt
echo -n "\"}" >> out.txt

# copy result file
cp out.txt cov_out_file.txt

cat cov_out_file.txt
# rm dummy files
rm out*.bak
rm out*.txt