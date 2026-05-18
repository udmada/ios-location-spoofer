lines = open('Resources/Info.plist', encoding='utf-8').readlines()
insert = [
    '\t<key>NSAppTransportSecurity</key>\n',
    '\t<dict>\n',
    '\t\t<key>NSAllowsArbitraryLoads</key>\n',
    '\t\t<true/>\n',
    '\t</dict>\n',
]
for i in range(len(lines)-1, -1, -1):
    if '</dict>' in lines[i]:
        for j, line in enumerate(insert):
            lines.insert(i+j, line)
        break
open('Resources/Info.plist','w',encoding='utf-8').writelines(lines)
print('done')
