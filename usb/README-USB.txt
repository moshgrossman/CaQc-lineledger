LINELEDGER ON A USB STICK
Accounting and Quebec payroll that runs from your pocket

Nothing gets installed. No admin rights. No internet needed.


-------------------------------------------------------------
SETTING IT UP - ONCE
-------------------------------------------------------------

1. Unzip the download onto the USB stick.

   Put the LineLedger folder at the TOP of the stick, not
   buried inside other folders. Windows still trips over very
   long folder names.

   When you are done the stick should look like this:

       E:\LineLedger\
           app\
           php\
           Data\
           Start LineLedger.bat
           Try the demo.bat
           first-run.php
           README-USB.txt

   Keep all of that together. Moving one folder out breaks it.

2. That's the whole setup. Nothing to install.


-------------------------------------------------------------
USING IT
-------------------------------------------------------------

Plug the stick into any Windows PC and double-click

    Start LineLedger.bat

The first time, it spends a few seconds setting itself up.
After that it opens in a few seconds.

LineLedger opens in its own window - no tabs, no address bar.
It looks like a program because that is how it is meant to
feel.

A small black window also opens and sits minimised on the
taskbar. That window IS LineLedger running.

    KEEP IT OPEN while you work.
    CLOSE IT when you are finished.

Closing it shuts everything down and makes the stick safe to
unplug.


-------------------------------------------------------------
WANT TO LOOK AROUND FIRST?
-------------------------------------------------------------

Double-click

    Try the demo.bat

That opens PRACTICE books instead - a made-up company with
invoices, two employees and a finished pay run already in it,
including a Quebec employee with QPP, QPIP and Quebec tax.

Break anything you like in there. It is a separate file and it
never touches your real books.

The window title says PRACTICE BOOKS so you always know which
one you are in.


-------------------------------------------------------------
YOUR BOOKS, AND BACKING THEM UP
-------------------------------------------------------------

Everything you enter lives in one file:

    Data\database.sqlite

To back up: copy the whole Data folder somewhere else - another
stick, a second folder, wherever. That is the entire backup
procedure. There is no export step.

Do this before anything that matters. It costs you ten seconds.

To restore: copy the folder back.


-------------------------------------------------------------
IF WINDOWS BLOCKS IT
-------------------------------------------------------------

The bundle includes php.exe - the engine that runs LineLedger.
It is the official build from php.net, but it is not signed by
Microsoft, so a cautious PC may object.

What you might see, and what to do:

* "Windows protected your PC" (blue box)
     Click "More info", then "Run anyway".

* Antivirus quarantines php.exe
     It is a false alarm, but you may not be able to override
     it on a machine that is not yours. If you cannot, this
     PC will not run LineLedger. Try another.

* The window flashes and vanishes
     Something failed instantly. Take a photo or screenshot of
     whatever it said, even briefly - that is what identifies
     the problem.

* "This folder is read-only"
     The stick's write-protect switch is on, or the folder is
     somewhere Windows guards. Move the LineLedger folder to
     the top level of the stick.


-------------------------------------------------------------
IF SOMETHING GOES WRONG
-------------------------------------------------------------

There is a minimised window on the taskbar called
"LineLedger server 8777". Open it. Whatever went wrong is
written in there.

A screenshot of that window is the single most useful thing
you can send. It usually identifies the problem outright.


-------------------------------------------------------------
THINGS WORTH KNOWING
-------------------------------------------------------------

* It runs on ONE PC at a time. Do not open the same stick on
  two machines at once.

* Always close the black window before unplugging. Yanking
  the stick mid-write is the one reliable way to damage your
  books.

* It is slow on first open - a USB stick reading 200 MB. A few
  seconds is normal. After that it is quick.

* Nothing is sent anywhere. No internet, no cloud, no account.
  Your payroll data never leaves the stick.

* This is LineLedger as its authors wrote it, just packaged to
  run from a stick. Known rough edge: on a cheque voucher for a
  Quebec employee the itemised deduction list leaves out QPP,
  QPIP and Quebec tax. The cheque total is correct.

* The tax rates need checking each January. LineLedger's own
  documentation says so. Always confirm a real paycheque
  against the government calculators - WebRAS for Quebec and
  PDOC for federal - before you pay anyone.


-------------------------------------------------------------

Built from LineLedger, which is free software under the AGPL.
The source is in the repository this came from.
