# Simple text input window to test key broadcasting (classic Win32 edit control)
# Usage: testinput.bat starts 3 copies
Add-Type -AssemblyName System.Windows.Forms
$form = New-Object System.Windows.Forms.Form
$form.Text = "Key test $PID"
$form.Size = New-Object System.Drawing.Size(500, 300)
$box = New-Object System.Windows.Forms.TextBox
$box.Multiline = $true
$box.Dock = "Fill"
$box.Font = New-Object System.Drawing.Font("Consolas", 14)
$form.Controls.Add($box)
$form.Add_Shown({ $box.Focus() })
[System.Windows.Forms.Application]::Run($form)
