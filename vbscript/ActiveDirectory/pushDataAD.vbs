Option Explicit
dim apiKey, secretKey, objHTTP, url, postData, resp, token, action, tag, monitorID, computer, oWMI, oRes, oEntry, value, unixDate, results, dtGMT, oResp, oNode, oGroup, aMembers, i, members

'You API key and Secret Key
apiKey = "your API key here"
secretKey = "your secret key here"

'Connecting to WMI, "." is for local computer, specify computer name for another computer
computer = "."
Set oWMI = GetObject("winmgmts:{impersonationLevel=impersonate,(Security)}!\\" + computer + "\root\cimv2")

'Finds current timezone to obtain GMT date
dtGMT = now
Set oRes = oWMI.ExecQuery("Select LocalDateTime from Win32_OperatingSystem")
For each oEntry in oRes
  dtGMT = DateAdd("n", -CInt(right(oEntry.LocalDateTime, 4)), dtGMT)
next

'Initialize HTTP connection object
Set objHTTP = CreateObject("Microsoft.XMLHTTP")

'Request a token to use in following calls
url = "http://www.monitis.com/api?action=authToken&apikey=" + apiKey + "&secretkey=" + secretKey
wscript.echo "Requesting token"
wscript.echo "GET: " + url
objHTTP.open "GET", url, False
objHTTP.send
resp = objHTTP.responseText
wscript.echo "Result: " + resp
token = DissectStr(resp, "authToken"":""", """")

'Requests the monitor list in order to find the MonitorID
tag = "[AD+sample]"
url = "http://www.monitis.com/customMonitorApi?action=getMonitors&apikey=" + apiKey + "&tag=" + tag + "&output=xml"
objHTTP.open "GET", url, False
wscript.echo "Requesting monitors list"
wscript.echo "GET: " + url
objHTTP.send
resp = objHTTP.responseText
wscript.echo "Result: " + resp

Set oResp = CreateObject("Microsoft.XMLDOM")
oResp.async = False
oResp.LoadXML(resp)

for each oNode in oResp.documentElement.childnodes
  if oNode.selectSingleNode("name").text = "AD group members" then 
    monitorID = oNode.selectSingleNode("id").text
	exit for
  end if
next

wscript.echo "Monitor ID: " + monitorID

Set oGroup = GetObject("LDAP://cn=ColorPrinter,cn=Users,dc=e2k10,dc=test")
oGroup.GetInfo
 
aMembers = oGroup.GetEx("member")

members = UBound(aMembers) + 1
wscript.echo "Group members : " & members

'Posts data
url = "http://www.monitis.com/customMonitorApi"
action = "addResult"
results = "members:" & members & ";"
unixDate = CStr(DateDiff("s", "01/01/1970 00:00:00", DateSerial(Year(dtGMT), Month(dtGMT), Day(dtGMT)) + TimeSerial(Hour(dtGMT), Minute(dtGMT), Second(dtGMT)))) + "000"
objHTTP.open "POST", url, False
objHTTP.setRequestHeader "Content-Type", "application/x-www-form-urlencoded"
postData = "apikey=" + apiKey + "&validation=token&authToken=" + token + "&timestamp=" + FmtDate(dtGMT) + "&action=" + action + "&monitorId=" + monitorID + "&checktime=" + unixDate + "&results=" + results
wscript.echo "Add monitor result"
wscript.echo "POST: " + url
wscript.echo "Data: " + postData
objHTTP.send postData
resp = objHTTP.responseText
wscript.echo "Result: " + resp

Function DissectStr(cString, cStart, cEnd)
  'Generic string manipulation function to extract value from JSON output
  dim nStart, nEnd
  nStart = InStr(cString, cStart)
  if nStart = 0 then 
    DissectStr = ""
  else
    nStart = nStart + len(cStart)
    if cEnd = "" then
      nEnd = len(cString)
    else
      nEnd = InStr(nStart, cString, cEnd)
      if nEnd = 0 then nEnd = nStart else nEnd = nEnd - nStart
    end if
    DissectStr = mid(cString, nStart, nEnd)
  end if
End Function

Function FmtDate(dt)
  FmtDate = cstr(Datepart("yyyy", dt)) + "-" + right("0" + cstr(Datepart("m", dt)),2) + "-" +  right("0" + cstr(Datepart ("d", dt)),2) + " " + right("0" + cstr(Datepart("h", dt)),2) + ":" + right("0" + cstr(Datepart("n", dt)),2) + ":" + right("0" + cstr(Datepart("S", dt)),2)
end function
