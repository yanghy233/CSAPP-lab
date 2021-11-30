#### 1 确定任务目标

本实验已经给定了一个tiny-shell的骨架，现要完成里面核心的7个功能组件，以便完善shell的功能；

##### 1.1 确定函数功能目标

> eval()：解析和解释命令行的主要例程；
>
> builtin_cmd()：识别并解释内置的命令，包括：quit, fg, bg, jobs;
>
> do_bgfg()：实现bg和fg的指令；
>
> waitfg()：等待一个前台工作的完成；
>
> sigchld_handler()：捕获SIGCHILD信号；
>
> sigint_handler()：捕获SIGINT信号；[ctrl + C]
>
> sigtstp_handler()：捕获SIGTSTP信号；[ctrl + Z]
&nbsp; 
&nbsp; 
##### 1.2 Basic Unix Operation

**1. 在指令末尾 + &：代表将指令丢到后台bg中，此时bash会给予这个指令一个job number**

<img src="images/image-20211130151039467.png" alt="image-20211130151039467" style="zoom:80%;" /> 

**2. ctrl + Z：将当前前台fg的工作丢到后台bg中暂停**（在vim的界面中ctrl+Z）

![image-20211130151307356](images/image-20211130151307356.png)

**3. jobs：观察目前后台bg下的所有工作状态** 

![image-20211130151259472](images/image-20211130151259472.png)
&nbsp; 

**4.  fg/bg：将后台工作拿到前台/前台处理**

```c
fg + %job_number : 当前界面切入vim程序（上例）
bg + %job_number : 将vim程序放入后台处理（上例）
```

![image-20211130151827722](images/image-20211130151827722.png)
&nbsp; 
**5. 显示所有允许着的进程**

静态：ps aux

动态：top

​    
&nbsp; 
&nbsp; 
##### 1.3 **General Overview of Unix Shells**

规定1：命令行第一个字要么是内置命令的名称，要么是可执行文件的路径名；

规定2：如果是内置命令，立即执行，否则将其视为可执行文件的路径名；

规定3：运行可执行文件时，shell分叉一个子进程，然后在子进程的上下文中加载并运行该程序；通过解释单个命令行而创建的子进程统称为作业；

规定4：一个作业可以由由Unix管道连接的多个子进程组成；以&结尾的，放入后台；

规定5：在任何时间点，最多可以在前景中运行一个作业。但是，任意数量的作业可以在后台运行；

规定6：键入ctrl-c会导致将SIGINT信号传递到前景作业中的每个过程中；终止进程

规定7：输入ctrl-z会将sigtstp信号传递到前景作业中的每个进程；暂停进程

​			当且仅当被SIGCONT信号唤醒

```c
tsh > jobs 			//这是运行内置命令：builtin cmd
tsh > /bin/ls		//运行的是程序
 
/*
jobs: List the running and stopped background jobs；

bg <job>: Change a stopped background job to a running background job； 
fg <job>: Change a stopped or running background job to a running in the 						foreground；
kill <job>: Terminate a job
```

  &nbsp; 
  &nbsp; 

##### 1.4  Specification实验要求

1、用户输入的命令行应该由一个名称和零个或多个参数组成，全部由一个或多个空格分隔。如果名称是一个内置的命令，那么tsh应该立即处理它，并等待下一个命令行。否则，tsh应该假设名称是可执行文件的路径，它在初始子进程的上下文中加载并运行（在此上下文中，术语作业指的是这个初始子进程）；

2、Tinyshell不需要支持管道（|）或I/O重定向（<和>）。

3、每个作业都可以通过进程ID(PID)或 job ID(JID)来标识，这是由tsh分配的正整数。jid应该在命令行上用前缀“%”表示。例如，“%5”表示JID5，而“5”表示PID5。（我们已经为您提供了操作作业列表所需的所有例程。

4、**builtin_cmd函数需要实现的功能如下：**

**–** The **quit** command terminates the shell.

**–** The **jobs** command lists all background jobs.

**–** The **bg <job>** command restarts <job> by sending it a SIGCONT signal, and then runs it in

the background. The <job> argument can be either a PID or a JID.

**–** The **fg <job>** command restarts <job> by sending it a SIGCONT signal, and then runs it in

the foreground. The <job> argument can be either a PID or a JID


&nbsp; 
eval函数的实现

> * eval - Evaluate the command line that the user has just typed in
> * If the user has requested a built-in command (quit, jobs, bg or fg)
> * then execute it immediately. Otherwise, fork a child process and
> * run the job in the context of the child. If the job is running in
> * the foreground, wait for it to terminate and then return.  Note:
> * each child process must have a unique process group ID so that our
> * background children don't receive SIGINT (SIGTSTP) from the kernel
> * when we type ctrl-c (ctrl-z) at the keyboard. 

```c
void eval(char *cmdline) {
    char *argv[MAXARGS];
    char buf[MAXLINE];      //作为cmdline的一个缓存
    int bg;
    pid_t pid;
    sigset_t mask;          //记录signal信号的集合

    strcpy(buf, cmdline);
    bg = parseline(buf, argv);      //分割字符串并确定是否要运行在后台, bg=1：后台执行
    if (argv[0] == NULL)
        return;

    if (!builtin_cmd(argv)) {         //非shell内置命令时，创建子进程
        //针对SIGINT,SIGTSTP,SIGCHLD三种信号进行屏蔽，创建进程的代码段不会被这些信号打断
        sigemptyset(&mask);
        sigaddset(&mask, SIGCHLD);
        sigaddset(&mask, SIGINT);
        sigaddset(&mask, SIGTSTP);
        sigprocmask(SIG_BLOCK, &mask, NULL);

        pid = Fork();

        if (pid == 0) {                           //子进程
            //子进程已创建，可重新开始使用信号
            sigprocmask(SIG_UNBLOCK, &mask, NULL);
            //创建进程组job，将当且进程放入
            if (setpgid(0, 0) < 0)
                unix_error("setpgid error");
            //now load and run the program in the new job, 开始运行
            if (execve(argv[0], argv, environ) < 0) {
                printf("%s: command not found\n", argv[0]);     //路径找不到
                exit(0);
            }
        } else {                                   //父进程
            //将子进程、进程组pid添加进进程表后，可重新开始使用信号
            addjob(jobs, pid, (bg == 1 ? BG : FG), cmdline);        //Add a job to the job list
            sigprocmask(SIG_UNBLOCK, &mask, NULL);

            //特判前后台
            if (!bg) {
                waitfg(pid);
            } else {
                printf("[%d] (%d) %s", pid2jid(pid), pid, cmdline);     //提示用户：放入后台
            }
        }

    }

    return;
}
```


&nbsp; 
builtin_cmd函数的实现

> builtin_cmd - If the user has typed a built-in command then execute it immediately. 

```c
int builtin_cmd(char **argv)        //当是shell内置命令时，执行它自己的
{
    if (!strcmp(argv[0], "quit"))    //equal
        exit(0);
    if (!strcmp(argv[0], "&"))       //ignore singleton &
        return 1;
    if (!strcmp(argv[0], "bg") || !strcmp(argv[0], "fg")) {
        do_bgfg(argv);              //前台后台统一处理
        return 1;
    }
    if (!strcmp(argv[0], "jobs")) {
        listjobs(jobs);
        return 1;
    }
    return 0;     /* not a builtin command */
}
```

&nbsp; 

do_bgfg函数的实现

> do_bgfg - Execute the builtin bg and fg commands

```c
void do_bgfg(char **argv) {
    struct job_t *job;     //存放获取到的job地址
    int pid = -1, jid = -1;

    if (argv[1] == NULL) {
        printf("%s command requires PID or %%jobid argument\n", argv[0]);
        return;
    }

    if (sscanf(argv[1], "%%%d", &jid) || sscanf(argv[1], "%d", &pid)) {
        if (jid != -1) {        //jid
            job = getjobjid(jobs, jid);             //jobs: job list
            if (job == NULL) {
                printf("%%%d: No such job\n", jid);
            }
                //bg success：[job_id] (pid) <argv>
                //fg success: Job [job_id] (pid) stopped by signal <xxx信号编号>
                //使用 kill(-(job->pid), SIGCONT)：发送信号SIGCONT给进程组abs(pid)
                //SIGCONT:用于通知暂停的进程继续
            else {
                pid = job->pid;
                if (!strcmp(argv[0], "bg")) {                 //bg
                    if (kill((pid), SIGCONT) < 0)
                        unix_error("kill (bg) error");
                    job->state = BG;
                    printf("[%d] (%d) %s\n", job->jid, job->pid, job->cmdline);
                } else {                                       //fg
                    if (kill((pid), SIGCONT) < 0)
                        unix_error("kill (bg) error");
                    job->state = FG;
                    waitfg(pid);
                }
            }
        } else {               //pid
            job = getjobpid(jobs, pid);
            if (job == NULL) {
                printf("(%d): No such process\n", pid);
            }
                //bg success：[job_id] (pid) <argv>
                //fg success: Job [job_id] (pid) stopped by signal <xxx信号编号>
                //使用 kill(-(job->pid), SIGCONT)：发送信号SIGCONT给进程组abs(pid)
                //SIGCONT:用于通知暂停的进程继续
            else {
                jid = job->jid;
                if (!strcmp(argv[0], "bg")) {                 //bg
                    if (kill((pid), SIGCONT) < 0)
                        unix_error("kill (bg) error");
                    job->state = BG;
                    printf("[%d] (%d) %s\n", job->jid, job->pid, job->cmdline);
                } else {                                       //fg
                    if (kill((pid), SIGCONT) < 0)
                        unix_error("kill (bg) error");
                    job->state = FG;
                    waitfg(pid);
                }
            }
        }
    } else {
        printf("%s: argument must be a PID or %%jobid\n", argv[0]);
    }


    return;
}
```
&nbsp; 


waitfg函数的实现

> waitfg - Block until process pid is no longer the foreground process

```c
void waitfg(pid_t pid)      // 目的：在进程处于前台期间，可以被任何信号打断
{
    sigset_t mask, prev;
    sigemptyset(&mask);
    while (fgpid(jobs) > 0) {        //不断检测前台是否有子进程
        sigprocmask(SIG_SETMASK, &mask, &prev);      //集合设为空，表示任意信号都能够对此进程阻塞
        sleep(1);
        sigprocmask(SIG_SETMASK, &prev, NULL);
    }
    return;
}
```


&nbsp; 
sigchld_handler的实现

> sigchld_handler：The kernel sends a SIGCHLD to the shell whenever
>
> - a child job terminates (becomes a zombie)
> -  or stops because it received a SIGSTOP or SIGTSTP signal. 
> - The handler reaps all available zombie children；
> - but doesn't wait for any other currently running children to terminate.  

主要作用：将僵死进程（terminated）回收delete掉，并且要判断这个进程是正常结束还是SIGINT或是SIGTSTP中断；此外，父进程在handler中不会等待其它正在运行的子进程终止，每次仅回收一个

```c
void sigchld_handler(int sig) //reap the zombie child: 回收所有的terminate状态的子进程
{
    int olderror = errno;
    pid_t pid;
    int status;
    sigset_t mask, prev;

    sigfillset(&mask);

    while ((pid = waitpid(-1, &status, WNOHANG | WUNTRACED)) > 0)   //父进程获取唯一的终止的子进程pid
    {
        if (WIFEXITED(status)) {      //若子进程是正常终止的
            sigprocmask(SIG_BLOCK, &mask, &prev);
            deletejob(jobs, pid);
            sigprocmask(SIG_BLOCK, &prev, NULL);
        }
        else if (WIFSIGNALED(status)){      //若子进程是被信号终止的
            struct job_t *job = getjobpid(jobs, pid);
            sigprocmask(SIG_BLOCK, &mask, &prev);
            // WTERMSIG(status):终止宏(int)
            printf("Job [%d] (%d) terminated by signal %d\n", job->jid, job->pid, WTERMSIG(status));
            deletejob(jobs, pid);
            sigprocmask(SIG_BLOCK, &prev, NULL);
        }
        else{           //若子进程是被信号暂停的
            struct job_t *job = getjobpid(jobs, pid);
            sigprocmask(SIG_BLOCK, &mask, &prev);
            // WSTOPSIG(status):暂停宏(int)
            printf("Job [%d] (%d) stopped by signal %d\n", job->jid, job->pid, WSTOPSIG(status));
            job->state= ST;         //设置job状态为stop
            sigprocmask(SIG_BLOCK, &prev, NULL);
        }
    }

    return;
}
```



&nbsp; 

sigint_handler的实现

> The kernel sends a SIGINT to the shell whenver the user types ctrl-c at the keyboard.  Catch it and send it along to the foreground job.

主要作用：收到ctrl+C后，捕获它并将它送至前台进程，终止前台进程

```c
void sigint_handler(int sig) {
    //获取前台进程pid
    int pid = fgpid(jobs);
    int jid = pid2jid(pid);
    sigset_t mask, prev;

    sigfillset(&mask);
    if(pid){
        sigprocmask(SIG_BLOCK, &mask, &prev);
        printf("Job [%d] (%d) terminated by signal 2\n",jid,pid);
        deletejob(jobs,pid);
        sigprocmask(SIG_SETMASK, &prev, NULL);
    }

    return;
}
```




&nbsp; 
sigtstp_handler的实现

> The kernel sends a SIGTSTP to the shell whenever the user types ctrl-z at the keyboard. Catch it and suspend the foreground job by sending it a SIGTSTP.

主要作用：收到ctrl+Z后，捕获它并将它送至前台进程，暂停前台进程

```c
void sigtstp_handler(int sig) {
    //获取前台进程pid
    int pid = fgpid(jobs);
    int jid = pid2jid(pid);
    sigset_t mask, prev;

    sigfillset(&mask);
    if(pid){
        sigprocmask(SIG_BLOCK, &mask, &prev);
        printf("Job [%d] (%d) terminated by signal 20\n",jid,pid);
        (*getjobpid(jobs,pid)).state = ST;      //设置job状态为stop
        sigprocmask(SIG_SETMASK, &prev, NULL);
    }


    return;
}
```

&nbsp; 



测试程序的正确性：

```c
make test01		//编译运行自己的
make rtest01	//编译运行reference的；最后
```

关于jobs，fg，bg的输出格式：

```c
struct job_t {              /* The job struct */
    pid_t pid;              /* job PID */
    int jid;                /* job ID [1, 2, ...] */
    int state;              /* UNDEF, BG, FG, or ST */
    char cmdline[MAXLINE];  /* command line */
};
struct job_t *getjobpid(struct job_t *jobs, pid_t pid);
struct job_t *getjobjid(struct job_t *jobs, int jid); 

//返回的是job_t指针，解引用得到对象，用state控制前后台位置即可！
    
/* 确认格式：
jobs：//List the running and stopped background jobs
	[job_id] (pid) Running <argv整段命令>
	[job_id] (pid) Stopped <argv整段命令>
	空				//空，代表没有任何job
	
bg %num:
	bg command requires PID or %jobid argument		//只有bg一个命令
	bg: argument must be a PID or %jobid			//argv[1]不是数字或者%数字
	(pid): No such process
	%jobid: No such job
	[job_id] (pid) <argv>
	空
	
fg %num:
	fg command requires PID or %jobid argument;
	fg: argument must be a PID or %jobid
    (pid): No such process
	%jobid: No such job
	空
```
&nbsp; 
&nbsp; 
关于sscanf()函数：

```cpp
//sscanf()函数用于从字符串中读取指定格式的数据，其原型如下：
int sscanf (char *str, char * format [, argument, ...]);

//返回值
//成功则返回参数数目argc，失败则返回-1，错误原因存于errno 中。

//用法
int num;
char lowercase[100];
sscanf(str,"%d %[a-z]", &num, lowercase);
//同理，带有%num
sscanf(str,"%%%d", &num);
```
&nbsp; 
&nbsp; 
关于kill()传递信号函数：

> 函数说明：kill(pid, sig_num)可以用来送参数sig 指定的信号给参数pid 指定的进程。参数pid 有几种情况：
>
> 1、pid>0 将信号传给**进程**识别码为pid 的进程.
>
> 2、pid=0 将信号传给和目前进程相同进程组的所有进程
>
> 3、pid=-1 将信号广播传送给系统内所有的进程
>
> 4、**pid<0** 将信号传给**进程组**识别码为pid 绝对值的**所有进程参数** sig 代表的信号编号可参考附录D


&nbsp; 

&nbsp; 
写一个快速测试所有样例的脚本：

单元测试: ./execute.sh 01~16

```bash
#! /bin/bash

mytest="test"
rtest="rtest"

make "$mytest$1" > my_ans.txt
make "$rtest$1" > correct_ans.txt
sed -i '1d' my_ans.txt			#删首行，无关的行
sed -i '1d' correct_ans.txt
echo "=======================test $1======================="
diff my_ans.txt correct_ans.txt > my_result.txt
if [[ ! -s "my_result.txt" ]]			#result是否为空
then
	echo "Success."
else
	cat my_result.txt
fi
```
&nbsp; 
&nbsp; 

所有样例一起跑	  ./execute.sh

注1：进程pid由操作系统自由分配，可能不一样，不由理会即可

注2：从test08开始，一定要自己手动输入CTRL + C才能结束，进行上述单元调试即可

```bash
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
```

&nbsp; 
&nbsp; 
&nbsp; 

Reference: 

[1] CS:APP:Lab6-*ShellLab* from 周小伦 https://www.zhihu.com/search?type=content&q=shelllab

[2] shlab.pdf from CMU

[3] lab6-shell.pdf from HIT

[4] 《CSAPP》第八章

[5] CSAPP实验shell lab from 林恩 https://zhuanlan.zhihu.com/p/89224358

