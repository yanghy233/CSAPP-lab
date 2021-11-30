#! /bin/bash

mytest="test"
rtest="rtest"
zero="0"

for((i=1;i<=16;i++))
do
	echo "=======================test $i======================="
	if [ "$i" -lt 10 ]
	then
		make "$mytest$zero$i" > my_ans.txt
		make "$rtest$zero$i" > correct_ans.txt		
	else
		make "$mytest$i" > my_ans.txt
		make "$rtest$i" > correct_ans.txt
	fi
	sed -i '1d' my_ans.txt			#删首行，无关的行
	sed -i '1d' correct_ans.txt
	diff my_ans.txt correct_ans.txt > my_result.txt
	if [[ ! -s "my_result.txt" ]]			#result是否为空
	then
		echo "Success."
	else
		cat my_result.txt
	fi
done
