# SPDX-License-Identifier: AGPL-3.0-only

















$script:UnifiedPublisherHostScriptBase64 = @'
W0NtZGxldEJpbmRpbmcoKV0KcGFyYW0oCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV1bc3RyaW5nXSRHc3RCaW4sCiAgICBbUGFyYW1ldGVy
KE1hbmRhdG9yeSA9ICR0cnVlKV1bc3RyaW5nXSRQaXBlbGluZUZpbGUsCiAgICBbVmFsaWRhdGVTZXQoJ0RlZmF1bHQnLCdNYXggYnVuZGxlJyldW3N0cmlu
Z10kQnVuZGxlUG9saWN5ID0gJ0RlZmF1bHQnLAogICAgW1ZhbGlkYXRlUmFuZ2UoMCw2NTUzNSldW2ludF0kSW50ZXJuYWxSdHBNdHUgPSAwLAogICAgW3N3
aXRjaF0kSW50ZXJuYWxSZXBlYXRIZWFkZXJzCikKCiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU3RvcCcKCmlmICgtbm90IChUZXN0LVBhdGggLUxpdGVy
YWxQYXRoICRQaXBlbGluZUZpbGUgLVBhdGhUeXBlIExlYWYpKSB7CiAgICB0aHJvdyAiVW5pZmllZCBwdWJsaXNoZXIgcGlwZWxpbmUgZmlsZSB3YXMgbm90
IGZvdW5kOiAkUGlwZWxpbmVGaWxlIgp9CmlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRHc3RCaW4gLVBhdGhUeXBlIENvbnRhaW5lcikpIHsK
ICAgIHRocm93ICJHU3RyZWFtZXIgYmluIGRpcmVjdG9yeSB3YXMgbm90IGZvdW5kOiAkR3N0QmluIgp9CgojIEN1cnJlbnQgR1N0cmVhbWVyIFdpbmRvd3Mg
cGFja2FnZXMgaGF2ZSB1c2VkIGJvdGggbGliLXByZWZpeGVkIGFuZAojIHVucHJlZml4ZWQgY29yZSBETEwgbmFtZXMuICBUaGUgbmF0aXZlIGhvc3QgaW1w
b3J0cyB0aGUgdHJhZGl0aW9uYWwKIyBsaWItcHJlZml4ZWQgbmFtZXMsIHNvIG1hdGVyaWFsaXplIHByaXZhdGUgYWxpYXNlcyB3aGVuIGEgbmV3ZXIgcnVu
dGltZSBvbmx5CiMgc2hpcHMgZ3N0cmVhbWVyLTEuMC0wLmRsbCAvIGdvYmplY3QtMi4wLTAuZGxsIC8gZ2xpYi0yLjAtMC5kbGwuCiRuYXRpdmVBbGlhc0Rp
ciA9IEpvaW4tUGF0aCAkZW52OkxPQ0FMQVBQREFUQSAnR1N0cmVhbWVyR2xhc3NcSGVscGVyc1xuYXRpdmUtYWxpYXNlcycKaWYgKC1ub3QgKFRlc3QtUGF0
aCAtTGl0ZXJhbFBhdGggJG5hdGl2ZUFsaWFzRGlyKSkgewogICAgJG51bGwgPSBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRuYXRpdmVB
bGlhc0RpciAtRm9yY2UKfQoKZnVuY3Rpb24gRW5zdXJlLU5hdGl2ZURsbEFsaWFzIHsKICAgIHBhcmFtKAogICAgICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5
ID0gJHRydWUpXVtzdHJpbmddJEltcG9ydE5hbWUsCiAgICAgICAgW1BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldW3N0cmluZ1tdXSRDYW5kaWRhdGVz
CiAgICApCgogICAgJGRpcmVjdCA9IEpvaW4tUGF0aCAkR3N0QmluICRJbXBvcnROYW1lCiAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZGlyZWN0
IC1QYXRoVHlwZSBMZWFmKSB7IHJldHVybiB9CgogICAgZm9yZWFjaCAoJGNhbmRpZGF0ZU5hbWUgaW4gJENhbmRpZGF0ZXMpIHsKICAgICAgICAkY2FuZGlk
YXRlID0gSm9pbi1QYXRoICRHc3RCaW4gJGNhbmRpZGF0ZU5hbWUKICAgICAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkY2FuZGlkYXRlIC1QYXRo
VHlwZSBMZWFmKSB7CiAgICAgICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJGNhbmRpZGF0ZSAtRGVzdGluYXRpb24gKEpvaW4tUGF0aCAkbmF0aXZl
QWxpYXNEaXIgJEltcG9ydE5hbWUpIC1Gb3JjZQogICAgICAgICAgICByZXR1cm4KICAgICAgICB9CiAgICB9CgogICAgdGhyb3cgIlJlcXVpcmVkIEdTdHJl
YW1lciBuYXRpdmUgRExMIHdhcyBub3QgZm91bmQuIEltcG9ydD0kSW1wb3J0TmFtZTsgc2VhcmNoZWQ9JCgkQ2FuZGlkYXRlcyAtam9pbiAnLCAnKSIKfQoK
RW5zdXJlLU5hdGl2ZURsbEFsaWFzIC1JbXBvcnROYW1lICdsaWJnc3RyZWFtZXItMS4wLTAuZGxsJyAtQ2FuZGlkYXRlcyBAKCdsaWJnc3RyZWFtZXItMS4w
LTAuZGxsJywnZ3N0cmVhbWVyLTEuMC0wLmRsbCcpCkVuc3VyZS1OYXRpdmVEbGxBbGlhcyAtSW1wb3J0TmFtZSAnbGliZ29iamVjdC0yLjAtMC5kbGwnIC1D
YW5kaWRhdGVzIEAoJ2xpYmdvYmplY3QtMi4wLTAuZGxsJywnZ29iamVjdC0yLjAtMC5kbGwnKQpFbnN1cmUtTmF0aXZlRGxsQWxpYXMgLUltcG9ydE5hbWUg
J2xpYmdsaWItMi4wLTAuZGxsJyAtQ2FuZGlkYXRlcyBAKCdsaWJnbGliLTIuMC0wLmRsbCcsJ2dsaWItMi4wLTAuZGxsJykKCiRlbnY6UEFUSCA9ICIkbmF0
aXZlQWxpYXNEaXI7JEdzdEJpbjskZW52OlBBVEgiCiRwaXBlbGluZURlc2NyaXB0aW9uID0gR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRQaXBlbGluZUZp
bGUgLVJhdwppZiAoW3N0cmluZ106OklzTnVsbE9yV2hpdGVTcGFjZSgkcGlwZWxpbmVEZXNjcmlwdGlvbikpIHsKICAgIHRocm93ICdVbmlmaWVkIHB1Ymxp
c2hlciBwaXBlbGluZSBkZXNjcmlwdGlvbiBpcyBlbXB0eS4nCn0KCiRuYXRpdmVTb3VyY2UgPSBAJwp1c2luZyBTeXN0ZW07CnVzaW5nIFN5c3RlbS5SdW50
aW1lLkludGVyb3BTZXJ2aWNlczsKdXNpbmcgU3lzdGVtLlRleHQ7CnVzaW5nIFN5c3RlbS5UaHJlYWRpbmc7CgpwdWJsaWMgc3RhdGljIGNsYXNzIEdTdHJl
YW1lckdsYXNzVW5pZmllZFB1Ymxpc2hlckhvc3QKewogICAgcHJpdmF0ZSBjb25zdCBpbnQgR1NUX1NUQVRFX05VTEwgPSAxOwogICAgcHJpdmF0ZSBjb25z
dCBpbnQgR1NUX1NUQVRFX1BMQVlJTkcgPSA0OwogICAgcHJpdmF0ZSBjb25zdCBpbnQgR1NUX1NUQVRFX0NIQU5HRV9GQUlMVVJFID0gMDsKICAgIHByaXZh
dGUgY29uc3QgdWludCBHU1RfTUVTU0FHRV9FUlJPUiA9IDF1IDw8IDE7CiAgICBwcml2YXRlIGNvbnN0IGludCBHX0NPTk5FQ1RfQUZURVIgPSAxOwoKICAg
IHByaXZhdGUgc3RhdGljIGJvb2wgX21heEJ1bmRsZTsKICAgIHByaXZhdGUgc3RhdGljIGludCBfaW50ZXJuYWxSdHBNdHU7CiAgICBwcml2YXRlIHN0YXRp
YyBib29sIF9yZXBlYXRIZWFkZXJzOwoKICAgIFtVbm1hbmFnZWRGdW5jdGlvblBvaW50ZXIoQ2FsbGluZ0NvbnZlbnRpb24uQ2RlY2wpXQogICAgcHJpdmF0
ZSBkZWxlZ2F0ZSB2b2lkIFdlYlJ0Y0JpblJlYWR5RGVsZWdhdGUoSW50UHRyIHNlbGYsIEludFB0ciBwZWVySWQsIEludFB0ciB3ZWJydGNiaW4sIEludFB0
ciB1c2VyRGF0YSk7CgogICAgW1VubWFuYWdlZEZ1bmN0aW9uUG9pbnRlcihDYWxsaW5nQ29udmVudGlvbi5DZGVjbCldCiAgICBwcml2YXRlIGRlbGVnYXRl
IGludCBQYXlsb2FkZXJTZXR1cERlbGVnYXRlKEludFB0ciBzZWxmLCBJbnRQdHIgY29uc3VtZXJJZCwgSW50UHRyIHBhZE5hbWUsIEludFB0ciBwYXlsb2Fk
ZXIsIEludFB0ciB1c2VyRGF0YSk7CgogICAgcHJpdmF0ZSBzdGF0aWMgV2ViUnRjQmluUmVhZHlEZWxlZ2F0ZSBfd2VicnRjYmluUmVhZHlEZWxlZ2F0ZSA9
IE9uV2ViUnRjQmluUmVhZHk7CiAgICBwcml2YXRlIHN0YXRpYyBQYXlsb2FkZXJTZXR1cERlbGVnYXRlIF9wYXlsb2FkZXJTZXR1cERlbGVnYXRlID0gT25Q
YXlsb2FkZXJTZXR1cDsKCiAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuU2VxdWVudGlhbCldCiAgICBwcml2YXRlIHN0cnVjdCBHRXJyb3JOYXRpdmUK
ICAgIHsKICAgICAgICBwdWJsaWMgdWludCBkb21haW47CiAgICAgICAgcHVibGljIGludCBjb2RlOwogICAgICAgIHB1YmxpYyBJbnRQdHIgbWVzc2FnZTsK
ICAgIH0KCiAgICBbRGxsSW1wb3J0KCJsaWJnc3RyZWFtZXItMS4wLTAuZGxsIiwgQ2FsbGluZ0NvbnZlbnRpb24gPSBDYWxsaW5nQ29udmVudGlvbi5DZGVj
bCldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gdm9pZCBnc3RfaW5pdChJbnRQdHIgYXJnYywgSW50UHRyIGFyZ3YpOwoKICAgIFtEbGxJbXBvcnQoImxp
YmdzdHJlYW1lci0xLjAtMC5kbGwiLCBDYWxsaW5nQ29udmVudGlvbiA9IENhbGxpbmdDb252ZW50aW9uLkNkZWNsKV0KICAgIHByaXZhdGUgc3RhdGljIGV4
dGVybiBJbnRQdHIgZ3N0X3BhcnNlX2xhdW5jaChbTWFyc2hhbEFzKFVubWFuYWdlZFR5cGUuTFBVVEY4U3RyKV0gc3RyaW5nIHBpcGVsaW5lRGVzY3JpcHRp
b24sIG91dCBJbnRQdHIgZXJyb3IpOwoKICAgIFtEbGxJbXBvcnQoImxpYmdzdHJlYW1lci0xLjAtMC5kbGwiLCBDYWxsaW5nQ29udmVudGlvbiA9IENhbGxp
bmdDb252ZW50aW9uLkNkZWNsKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBJbnRQdHIgZ3N0X2Jpbl9nZXRfYnlfbmFtZShJbnRQdHIgYmluLCBbTWFy
c2hhbEFzKFVubWFuYWdlZFR5cGUuTFBVVEY4U3RyKV0gc3RyaW5nIG5hbWUpOwoKICAgIFtEbGxJbXBvcnQoImxpYmdzdHJlYW1lci0xLjAtMC5kbGwiLCBD
YWxsaW5nQ29udmVudGlvbiA9IENhbGxpbmdDb252ZW50aW9uLkNkZWNsKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBpbnQgZ3N0X2VsZW1lbnRfc2V0
X3N0YXRlKEludFB0ciBlbGVtZW50LCBpbnQgc3RhdGUpOwoKICAgIFtEbGxJbXBvcnQoImxpYmdzdHJlYW1lci0xLjAtMC5kbGwiLCBDYWxsaW5nQ29udmVu
dGlvbiA9IENhbGxpbmdDb252ZW50aW9uLkNkZWNsKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBJbnRQdHIgZ3N0X2VsZW1lbnRfZ2V0X2J1cyhJbnRQ
dHIgZWxlbWVudCk7CgogICAgW0RsbEltcG9ydCgibGliZ3N0cmVhbWVyLTEuMC0wLmRsbCIsIENhbGxpbmdDb252ZW50aW9uID0gQ2FsbGluZ0NvbnZlbnRp
b24uQ2RlY2wpXQogICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIEludFB0ciBnc3RfYnVzX3RpbWVkX3BvcF9maWx0ZXJlZChJbnRQdHIgYnVzLCB1bG9uZyB0
aW1lb3V0LCB1aW50IHR5cGVzKTsKCiAgICBbRGxsSW1wb3J0KCJsaWJnc3RyZWFtZXItMS4wLTAuZGxsIiwgQ2FsbGluZ0NvbnZlbnRpb24gPSBDYWxsaW5n
Q29udmVudGlvbi5DZGVjbCldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gdm9pZCBnc3RfbWVzc2FnZV9wYXJzZV9lcnJvcihJbnRQdHIgbWVzc2FnZSwg
b3V0IEludFB0ciBlcnJvciwgb3V0IEludFB0ciBkZWJ1Zyk7CgogICAgW0RsbEltcG9ydCgibGliZ3N0cmVhbWVyLTEuMC0wLmRsbCIsIENhbGxpbmdDb252
ZW50aW9uID0gQ2FsbGluZ0NvbnZlbnRpb24uQ2RlY2wpXQogICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIHZvaWQgZ3N0X21pbmlfb2JqZWN0X3VucmVmKElu
dFB0ciBtaW5pT2JqZWN0KTsKCiAgICBbRGxsSW1wb3J0KCJsaWJnc3RyZWFtZXItMS4wLTAuZGxsIiwgQ2FsbGluZ0NvbnZlbnRpb24gPSBDYWxsaW5nQ29u
dmVudGlvbi5DZGVjbCldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gdm9pZCBnc3Rfb2JqZWN0X3VucmVmKEludFB0ciBvYmopOwoKICAgIFtEbGxJbXBv
cnQoImxpYmdzdHJlYW1lci0xLjAtMC5kbGwiLCBDYWxsaW5nQ29udmVudGlvbiA9IENhbGxpbmdDb252ZW50aW9uLkNkZWNsKV0KICAgIHByaXZhdGUgc3Rh
dGljIGV4dGVybiB2b2lkIGdzdF91dGlsX3NldF9vYmplY3RfYXJnKEludFB0ciBvYmosIFtNYXJzaGFsQXMoVW5tYW5hZ2VkVHlwZS5MUFVURjhTdHIpXSBz
dHJpbmcgbmFtZSwgW01hcnNoYWxBcyhVbm1hbmFnZWRUeXBlLkxQVVRGOFN0cildIHN0cmluZyB2YWx1ZSk7CgogICAgW0RsbEltcG9ydCgibGliZ29iamVj
dC0yLjAtMC5kbGwiLCBDYWxsaW5nQ29udmVudGlvbiA9IENhbGxpbmdDb252ZW50aW9uLkNkZWNsKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiB1aW50
IGdfc2lnbmFsX2Nvbm5lY3RfZGF0YSgKICAgICAgICBJbnRQdHIgaW5zdGFuY2UsCiAgICAgICAgW01hcnNoYWxBcyhVbm1hbmFnZWRUeXBlLkxQVVRGOFN0
cildIHN0cmluZyBkZXRhaWxlZFNpZ25hbCwKICAgICAgICBJbnRQdHIgY2FsbGJhY2ssCiAgICAgICAgSW50UHRyIGRhdGEsCiAgICAgICAgSW50UHRyIGRl
c3Ryb3lEYXRhLAogICAgICAgIGludCBjb25uZWN0RmxhZ3MpOwoKICAgIFtEbGxJbXBvcnQoImxpYmdsaWItMi4wLTAuZGxsIiwgQ2FsbGluZ0NvbnZlbnRp
b24gPSBDYWxsaW5nQ29udmVudGlvbi5DZGVjbCldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gdm9pZCBnX2Vycm9yX2ZyZWUoSW50UHRyIGVycm9yKTsK
CiAgICBbRGxsSW1wb3J0KCJsaWJnbGliLTIuMC0wLmRsbCIsIENhbGxpbmdDb252ZW50aW9uID0gQ2FsbGluZ0NvbnZlbnRpb24uQ2RlY2wpXQogICAgcHJp
dmF0ZSBzdGF0aWMgZXh0ZXJuIHZvaWQgZ19mcmVlKEludFB0ciBtZW1vcnkpOwoKICAgIHByaXZhdGUgc3RhdGljIHN0cmluZyBQdHJUb1V0ZjgoSW50UHRy
IHB0cikKICAgIHsKICAgICAgICBpZiAocHRyID09IEludFB0ci5aZXJvKSByZXR1cm4gU3RyaW5nLkVtcHR5OwogICAgICAgIGludCBsZW5ndGggPSAwOwog
ICAgICAgIHdoaWxlIChNYXJzaGFsLlJlYWRCeXRlKHB0ciwgbGVuZ3RoKSAhPSAwKSBsZW5ndGgrKzsKICAgICAgICBpZiAobGVuZ3RoID09IDApIHJldHVy
biBTdHJpbmcuRW1wdHk7CiAgICAgICAgYnl0ZVtdIGJ5dGVzID0gbmV3IGJ5dGVbbGVuZ3RoXTsKICAgICAgICBNYXJzaGFsLkNvcHkocHRyLCBieXRlcywg
MCwgbGVuZ3RoKTsKICAgICAgICByZXR1cm4gRW5jb2RpbmcuVVRGOC5HZXRTdHJpbmcoYnl0ZXMpOwogICAgfQoKICAgIHByaXZhdGUgc3RhdGljIHN0cmlu
ZyBSZWFkR0Vycm9yKEludFB0ciBlcnJvcikKICAgIHsKICAgICAgICBpZiAoZXJyb3IgPT0gSW50UHRyLlplcm8pIHJldHVybiBTdHJpbmcuRW1wdHk7CiAg
ICAgICAgR0Vycm9yTmF0aXZlIG5hdGl2ZSA9IChHRXJyb3JOYXRpdmUpTWFyc2hhbC5QdHJUb1N0cnVjdHVyZShlcnJvciwgdHlwZW9mKEdFcnJvck5hdGl2
ZSkpOwogICAgICAgIHJldHVybiBQdHJUb1V0ZjgobmF0aXZlLm1lc3NhZ2UpOwogICAgfQoKICAgIHByaXZhdGUgc3RhdGljIHZvaWQgT25XZWJSdGNCaW5S
ZWFkeShJbnRQdHIgc2VsZiwgSW50UHRyIHBlZXJJZCwgSW50UHRyIHdlYnJ0Y2JpbiwgSW50UHRyIHVzZXJEYXRhKQogICAgewogICAgICAgIGlmICghX21h
eEJ1bmRsZSB8fCB3ZWJydGNiaW4gPT0gSW50UHRyLlplcm8pIHJldHVybjsKICAgICAgICBzdHJpbmcgcGVlciA9IFB0clRvVXRmOChwZWVySWQpOwogICAg
ICAgIGdzdF91dGlsX3NldF9vYmplY3RfYXJnKHdlYnJ0Y2JpbiwgImJ1bmRsZS1wb2xpY3kiLCAibWF4LWJ1bmRsZSIpOwogICAgICAgIENvbnNvbGUuV3Jp
dGVMaW5lKCJbdW5pZmllZC1ob3N0XSB3ZWJydGNiaW4tcmVhZHkgcGVlcj0iICsgcGVlciArICIgYnVuZGxlLXBvbGljeT1tYXgtYnVuZGxlIik7CiAgICB9
CgogICAgcHJpdmF0ZSBzdGF0aWMgaW50IE9uUGF5bG9hZGVyU2V0dXAoSW50UHRyIHNlbGYsIEludFB0ciBjb25zdW1lcklkLCBJbnRQdHIgcGFkTmFtZSwg
SW50UHRyIHBheWxvYWRlciwgSW50UHRyIHVzZXJEYXRhKQogICAgewogICAgICAgIGlmIChwYXlsb2FkZXIgPT0gSW50UHRyLlplcm8pIHJldHVybiAwOwog
ICAgICAgIHN0cmluZyBjb25zdW1lciA9IFB0clRvVXRmOChjb25zdW1lcklkKTsKICAgICAgICBzdHJpbmcgcGFkID0gUHRyVG9VdGY4KHBhZE5hbWUpOwoK
ICAgICAgICBpZiAoX2ludGVybmFsUnRwTXR1ID4gMCkKICAgICAgICB7CiAgICAgICAgICAgIGdzdF91dGlsX3NldF9vYmplY3RfYXJnKHBheWxvYWRlciwg
Im10dSIsIF9pbnRlcm5hbFJ0cE10dS5Ub1N0cmluZygpKTsKICAgICAgICAgICAgQ29uc29sZS5Xcml0ZUxpbmUoIlt1bmlmaWVkLWhvc3RdIHBheWxvYWRl
ci1zZXR1cCBjb25zdW1lcj0iICsgY29uc3VtZXIgKyAiIHBhZD0iICsgcGFkICsgIiBtdHU9IiArIF9pbnRlcm5hbFJ0cE10dSk7CiAgICAgICAgfQoKICAg
ICAgICBpZiAoX3JlcGVhdEhlYWRlcnMgJiYgcGFkLlN0YXJ0c1dpdGgoInZpZGVvXyIsIFN0cmluZ0NvbXBhcmlzb24uT3JkaW5hbElnbm9yZUNhc2UpKQog
ICAgICAgIHsKICAgICAgICAgICAgZ3N0X3V0aWxfc2V0X29iamVjdF9hcmcocGF5bG9hZGVyLCAiY29uZmlnLWludGVydmFsIiwgIi0xIik7CiAgICAgICAg
ICAgIENvbnNvbGUuV3JpdGVMaW5lKCJbdW5pZmllZC1ob3N0XSBwYXlsb2FkZXItc2V0dXAgY29uc3VtZXI9IiArIGNvbnN1bWVyICsgIiBwYWQ9IiArIHBh
ZCArICIgY29uZmlnLWludGVydmFsPS0xIik7CiAgICAgICAgfQoKICAgICAgICByZXR1cm4gMTsKICAgIH0KCiAgICBwcml2YXRlIHN0YXRpYyB1aW50IENv
bm5lY3RTaWduYWwoSW50UHRyIGluc3RhbmNlLCBzdHJpbmcgc2lnbmFsLCBEZWxlZ2F0ZSBjYWxsYmFjaywgaW50IGZsYWdzKQogICAgewogICAgICAgIElu
dFB0ciBmdW5jdGlvblBvaW50ZXIgPSBNYXJzaGFsLkdldEZ1bmN0aW9uUG9pbnRlckZvckRlbGVnYXRlKGNhbGxiYWNrKTsKICAgICAgICByZXR1cm4gZ19z
aWduYWxfY29ubmVjdF9kYXRhKGluc3RhbmNlLCBzaWduYWwsIGZ1bmN0aW9uUG9pbnRlciwgSW50UHRyLlplcm8sIEludFB0ci5aZXJvLCBmbGFncyk7CiAg
ICB9CgogICAgcHVibGljIHN0YXRpYyBpbnQgUnVuKHN0cmluZyBwaXBlbGluZURlc2NyaXB0aW9uLCBib29sIG1heEJ1bmRsZSwgaW50IGludGVybmFsUnRw
TXR1LCBib29sIHJlcGVhdEhlYWRlcnMpCiAgICB7CiAgICAgICAgX21heEJ1bmRsZSA9IG1heEJ1bmRsZTsKICAgICAgICBfaW50ZXJuYWxSdHBNdHUgPSBp
bnRlcm5hbFJ0cE10dTsKICAgICAgICBfcmVwZWF0SGVhZGVycyA9IHJlcGVhdEhlYWRlcnM7CgogICAgICAgIEludFB0ciBwaXBlbGluZSA9IEludFB0ci5a
ZXJvOwogICAgICAgIEludFB0ciBzaW5rID0gSW50UHRyLlplcm87CiAgICAgICAgSW50UHRyIGJ1cyA9IEludFB0ci5aZXJvOwogICAgICAgIEludFB0ciBw
YXJzZUVycm9yID0gSW50UHRyLlplcm87CgogICAgICAgIHRyeQogICAgICAgIHsKICAgICAgICAgICAgZ3N0X2luaXQoSW50UHRyLlplcm8sIEludFB0ci5a
ZXJvKTsKICAgICAgICAgICAgcGlwZWxpbmUgPSBnc3RfcGFyc2VfbGF1bmNoKHBpcGVsaW5lRGVzY3JpcHRpb24sIG91dCBwYXJzZUVycm9yKTsKICAgICAg
ICAgICAgaWYgKHBpcGVsaW5lID09IEludFB0ci5aZXJvKQogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICBzdHJpbmcgcGFyc2VNZXNzYWdlID0gUmVh
ZEdFcnJvcihwYXJzZUVycm9yKTsKICAgICAgICAgICAgICAgIENvbnNvbGUuRXJyb3IuV3JpdGVMaW5lKCJbdW5pZmllZC1ob3N0XSBnc3RfcGFyc2VfbGF1
bmNoIGZhaWxlZDogIiArIHBhcnNlTWVzc2FnZSk7CiAgICAgICAgICAgICAgICByZXR1cm4gMTsKICAgICAgICAgICAgfQoKICAgICAgICAgICAgc2luayA9
IGdzdF9iaW5fZ2V0X2J5X25hbWUocGlwZWxpbmUsICJvdXQiKTsKICAgICAgICAgICAgaWYgKHNpbmsgPT0gSW50UHRyLlplcm8pCiAgICAgICAgICAgIHsK
ICAgICAgICAgICAgICAgIENvbnNvbGUuRXJyb3IuV3JpdGVMaW5lKCJbdW5pZmllZC1ob3N0XSB3ZWJydGNzaW5rIG5hbWVkICdvdXQnIHdhcyBub3QgZm91
bmQuIik7CiAgICAgICAgICAgICAgICByZXR1cm4gMTsKICAgICAgICAgICAgfQoKICAgICAgICAgICAgaWYgKF9tYXhCdW5kbGUpCiAgICAgICAgICAgIHsK
ICAgICAgICAgICAgICAgIENvbm5lY3RTaWduYWwoc2luaywgIndlYnJ0Y2Jpbi1yZWFkeSIsIF93ZWJydGNiaW5SZWFkeURlbGVnYXRlLCAwKTsKICAgICAg
ICAgICAgfQogICAgICAgICAgICBpZiAoX2ludGVybmFsUnRwTXR1ID4gMCB8fCBfcmVwZWF0SGVhZGVycykKICAgICAgICAgICAgewogICAgICAgICAgICAg
ICAgQ29ubmVjdFNpZ25hbChzaW5rLCAicGF5bG9hZGVyLXNldHVwIiwgX3BheWxvYWRlclNldHVwRGVsZWdhdGUsIEdfQ09OTkVDVF9BRlRFUik7CiAgICAg
ICAgICAgIH0KCiAgICAgICAgICAgIENvbnNvbGUuV3JpdGVMaW5lKCJbdW5pZmllZC1ob3N0XSBwaXBlbGluZSBzdGFydGluZzsgbWF4LWJ1bmRsZT0iICsg
X21heEJ1bmRsZSArICI7IGludGVybmFsLW10dT0iICsgX2ludGVybmFsUnRwTXR1ICsgIjsgcmVwZWF0LWhlYWRlcnM9IiArIF9yZXBlYXRIZWFkZXJzKTsK
ICAgICAgICAgICAgaW50IHN0YXRlUmVzdWx0ID0gZ3N0X2VsZW1lbnRfc2V0X3N0YXRlKHBpcGVsaW5lLCBHU1RfU1RBVEVfUExBWUlORyk7CiAgICAgICAg
ICAgIGlmIChzdGF0ZVJlc3VsdCA9PSBHU1RfU1RBVEVfQ0hBTkdFX0ZBSUxVUkUpCiAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgIENvbnNvbGUuRXJy
b3IuV3JpdGVMaW5lKCJbdW5pZmllZC1ob3N0XSBmYWlsZWQgdG8gc2V0IHBpcGVsaW5lIHRvIFBMQVlJTkcuIik7CiAgICAgICAgICAgICAgICByZXR1cm4g
MTsKICAgICAgICAgICAgfQoKICAgICAgICAgICAgYnVzID0gZ3N0X2VsZW1lbnRfZ2V0X2J1cyhwaXBlbGluZSk7CiAgICAgICAgICAgIHdoaWxlICh0cnVl
KQogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICBJbnRQdHIgbWVzc2FnZSA9IGdzdF9idXNfdGltZWRfcG9wX2ZpbHRlcmVkKGJ1cywgMjUwMDAwMDAw
VUwsIEdTVF9NRVNTQUdFX0VSUk9SKTsKICAgICAgICAgICAgICAgIGlmIChtZXNzYWdlICE9IEludFB0ci5aZXJvKQogICAgICAgICAgICAgICAgewogICAg
ICAgICAgICAgICAgICAgIEludFB0ciBlcnJvciA9IEludFB0ci5aZXJvOwogICAgICAgICAgICAgICAgICAgIEludFB0ciBkZWJ1ZyA9IEludFB0ci5aZXJv
OwogICAgICAgICAgICAgICAgICAgIHRyeQogICAgICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICAgICAgZ3N0X21lc3NhZ2VfcGFyc2Vf
ZXJyb3IobWVzc2FnZSwgb3V0IGVycm9yLCBvdXQgZGVidWcpOwogICAgICAgICAgICAgICAgICAgICAgICBDb25zb2xlLkVycm9yLldyaXRlTGluZSgiW3Vu
aWZpZWQtaG9zdF0gR1N0cmVhbWVyIGVycm9yOiAiICsgUmVhZEdFcnJvcihlcnJvcikpOwogICAgICAgICAgICAgICAgICAgICAgICBzdHJpbmcgZGVidWdU
ZXh0ID0gUHRyVG9VdGY4KGRlYnVnKTsKICAgICAgICAgICAgICAgICAgICAgICAgaWYgKCFTdHJpbmcuSXNOdWxsT3JXaGl0ZVNwYWNlKGRlYnVnVGV4dCkp
IENvbnNvbGUuRXJyb3IuV3JpdGVMaW5lKCJbdW5pZmllZC1ob3N0XSAiICsgZGVidWdUZXh0KTsKICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAg
ICAgICAgICAgZmluYWxseQogICAgICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICAgICAgaWYgKGVycm9yICE9IEludFB0ci5aZXJvKSBn
X2Vycm9yX2ZyZWUoZXJyb3IpOwogICAgICAgICAgICAgICAgICAgICAgICBpZiAoZGVidWcgIT0gSW50UHRyLlplcm8pIGdfZnJlZShkZWJ1Zyk7CiAgICAg
ICAgICAgICAgICAgICAgICAgIGdzdF9taW5pX29iamVjdF91bnJlZihtZXNzYWdlKTsKICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAg
ICAgcmV0dXJuIDE7CiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICBUaHJlYWQuU2xlZXAoMTApOwogICAgICAgICAgICB9CiAgICAgICAgfQog
ICAgICAgIGNhdGNoIChFeGNlcHRpb24gZXgpCiAgICAgICAgewogICAgICAgICAgICBDb25zb2xlLkVycm9yLldyaXRlTGluZSgiW3VuaWZpZWQtaG9zdF0g
ZmF0YWw6ICIgKyBleCk7CiAgICAgICAgICAgIHJldHVybiAxOwogICAgICAgIH0KICAgICAgICBmaW5hbGx5CiAgICAgICAgewogICAgICAgICAgICBpZiAo
cGlwZWxpbmUgIT0gSW50UHRyLlplcm8pIGdzdF9lbGVtZW50X3NldF9zdGF0ZShwaXBlbGluZSwgR1NUX1NUQVRFX05VTEwpOwogICAgICAgICAgICBpZiAo
YnVzICE9IEludFB0ci5aZXJvKSBnc3Rfb2JqZWN0X3VucmVmKGJ1cyk7CiAgICAgICAgICAgIGlmIChzaW5rICE9IEludFB0ci5aZXJvKSBnc3Rfb2JqZWN0
X3VucmVmKHNpbmspOwogICAgICAgICAgICBpZiAocGlwZWxpbmUgIT0gSW50UHRyLlplcm8pIGdzdF9vYmplY3RfdW5yZWYocGlwZWxpbmUpOwogICAgICAg
ICAgICBpZiAocGFyc2VFcnJvciAhPSBJbnRQdHIuWmVybykgZ19lcnJvcl9mcmVlKHBhcnNlRXJyb3IpOwogICAgICAgIH0KICAgIH0KfQonQAoKQWRkLVR5
cGUgLVR5cGVEZWZpbml0aW9uICRuYXRpdmVTb3VyY2UgLUxhbmd1YWdlIENTaGFycApleGl0IFtHU3RyZWFtZXJHbGFzc1VuaWZpZWRQdWJsaXNoZXJIb3N0
XTo6UnVuKAogICAgJHBpcGVsaW5lRGVzY3JpcHRpb24sCiAgICAoJEJ1bmRsZVBvbGljeSAtZXEgJ01heCBidW5kbGUnKSwKICAgICRJbnRlcm5hbFJ0cE10
dSwKICAgIFtib29sXSRJbnRlcm5hbFJlcGVhdEhlYWRlcnMKKQo=
'@






























$script:AppIcon = Get-ApplicationIcon

$form = New-Object System.Windows.Forms.Form
$form.Text = $script:AppName
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1640, 960)
$form.MinimumSize = New-Object System.Drawing.Size(1280, 760)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Icon = $script:AppIcon

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 15000
$toolTip.InitialDelay = 350
$toolTip.ReshowDelay = 100



$settingsGroup = New-Object System.Windows.Forms.GroupBox
$settingsGroup.Text = 'Stream Settings'
$settingsGroup.Location = New-Object System.Drawing.Point(10, 10)
$settingsGroup.Size = New-Object System.Drawing.Size(735, 586)
$form.Controls.Add($settingsGroup)

$null = Add-Label $settingsGroup 'GStreamer executable' 15 25 130
$txtGstPath = New-Object System.Windows.Forms.TextBox
$txtGstPath.Location = New-Object System.Drawing.Point(150, 25)
$txtGstPath.Size = New-Object System.Drawing.Size(370, 23)
$txtGstPath.Text = Find-GstLaunch
$settingsGroup.Controls.Add($txtGstPath)
$toolTip.SetToolTip($txtGstPath, 'Fresh installs prefer C:\Program Files\gstreamer\1.0\msvc_x86_64\bin\gst-launch-1.0.exe. A valid user-selected binary is preserved and gets its own plugin/scanner/registry environment; Strom is fallback only.')

$btnBrowseGst = New-Object System.Windows.Forms.Button
$btnBrowseGst.Text = 'Browse...'
$btnBrowseGst.Location = New-Object System.Drawing.Point(530, 23)
$btnBrowseGst.Size = New-Object System.Drawing.Size(60, 27)
$settingsGroup.Controls.Add($btnBrowseGst)

$btnDetectGst = New-Object System.Windows.Forms.Button
$btnDetectGst.Text = 'Detect'
$btnDetectGst.Location = New-Object System.Drawing.Point(595, 23)
$btnDetectGst.Size = New-Object System.Drawing.Size(60, 27)
$settingsGroup.Controls.Add($btnDetectGst)
$toolTip.SetToolTip($btnDetectGst, 'Finds Strom bundled GStreamer first, then the official/default installations.')

$btnCheckGst = New-Object System.Windows.Forms.Button
$btnCheckGst.Text = 'Check'
$btnCheckGst.Location = New-Object System.Drawing.Point(660, 23)
$btnCheckGst.Size = New-Object System.Drawing.Size(58, 27)
$settingsGroup.Controls.Add($btnCheckGst)
$toolTip.SetToolTip($btnCheckGst, 'Checks every GStreamer element required by the selected encoder, protocol, preview, and audio configuration.')

$null = Add-Label $settingsGroup 'Protocol' 15 60 70
$cmbProtocol = New-Object System.Windows.Forms.ComboBox
$cmbProtocol.Location = New-Object System.Drawing.Point(85, 60)
$cmbProtocol.Size = New-Object System.Drawing.Size(100, 23)
$cmbProtocol.DropDownStyle = 'DropDownList'
$null = $cmbProtocol.Items.AddRange(@('WHIP', 'GST WebRTC', 'SRT', 'RTMP', 'RTSP'))
$cmbProtocol.SelectedItem = 'WHIP'
$settingsGroup.Controls.Add($cmbProtocol)

$chkTransportEnabled = New-Object System.Windows.Forms.CheckBox
$chkTransportEnabled.Text = 'Enable transport'
$chkTransportEnabled.Location = New-Object System.Drawing.Point(15, 32)
$chkTransportEnabled.Size = New-Object System.Drawing.Size(160, 24)
$chkTransportEnabled.Checked = $true
$settingsGroup.Controls.Add($chkTransportEnabled)
$toolTip.SetToolTip($chkTransportEnabled, 'Enables the network transport sink (WHIP/SRT/RTMP/RTSP). Disable this for local recording/preview only.')

$lblDestination = Add-Label $settingsGroup 'WHIP endpoint' 200 60 100
$txtDestination = New-Object System.Windows.Forms.TextBox
$txtDestination.Location = New-Object System.Drawing.Point(300, 60)
$txtDestination.Size = New-Object System.Drawing.Size(418, 23)
$txtDestination.Text = $script:ProtocolDestinations.WHIP
$settingsGroup.Controls.Add($txtDestination)

$cmbCaptureMethod = New-Object System.Windows.Forms.ComboBox
$cmbCaptureMethod.Location = New-Object System.Drawing.Point(15, 96)
$cmbCaptureMethod.Size = New-Object System.Drawing.Size(245, 23)
$cmbCaptureMethod.DropDownStyle = 'DropDownList'
$null = $cmbCaptureMethod.Items.AddRange(@($script:CaptureMethodCatalog.Keys))
$cmbCaptureMethod.SelectedItem = $script:DefaultCaptureMethodName
$settingsGroup.Controls.Add($cmbCaptureMethod)
$toolTip.SetToolTip($cmbCaptureMethod, 'Choose the GStreamer capture backend. Try Monitor - D3D11 / WGC when Sunshine/Moonlight breaks whole-display DXGI capture.')

# Legacy compatibility flag for older settings and event paths. Hidden now that
# capture is controlled by the Capture Method dropdown.
$chkFullscreenApp = New-Object System.Windows.Forms.CheckBox
$chkFullscreenApp.Text = 'Only capture fullscreen app (WGC)'
$chkFullscreenApp.Location = New-Object System.Drawing.Point(15, 96)
$chkFullscreenApp.Size = New-Object System.Drawing.Size(245, 25)
$chkFullscreenApp.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$chkFullscreenApp.Checked = $false
$settingsGroup.Controls.Add($chkFullscreenApp)
$toolTip.SetToolTip($chkFullscreenApp, 'Legacy compatibility flag. Use the Capture Method dropdown instead.')
$chkFullscreenApp.Visible = $false
$chkFullscreenApp.TabStop = $false

$lblCaptureModeStatus = New-Object System.Windows.Forms.Label
$lblCaptureModeStatus.Text = 'Monitor capture active'
$lblCaptureModeStatus.Location = New-Object System.Drawing.Point(275, 96)
$lblCaptureModeStatus.Size = New-Object System.Drawing.Size(300, 25)
$lblCaptureModeStatus.TextAlign = 'MiddleLeft'
$lblCaptureModeStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblCaptureModeStatus)

$chkStartMinimized = New-Object System.Windows.Forms.CheckBox
$chkStartMinimized.Text = 'Start minimized'
$chkStartMinimized.Location = New-Object System.Drawing.Point(600, 96)
$chkStartMinimized.Size = New-Object System.Drawing.Size(125, 25)
$chkStartMinimized.Checked = $false
$settingsGroup.Controls.Add($chkStartMinimized)
$toolTip.SetToolTip($chkStartMinimized, 'Starts the app directly in the notification area. Enabling this requires and automatically enables Minimize to tray.')

$null = Add-Label $settingsGroup 'Monitor' 15 130 60
$numMonitor = New-Object System.Windows.Forms.NumericUpDown
$numMonitor.Location = New-Object System.Drawing.Point(75, 130)
$numMonitor.Size = New-Object System.Drawing.Size(60, 23)
$numMonitor.Minimum = -1
$numMonitor.Maximum = 32
$numMonitor.Value = -1
$settingsGroup.Controls.Add($numMonitor)
$toolTip.SetToolTip($numMonitor, '-1 uses the primary monitor. Other values select a GStreamer monitor index.')

$chkCursor = New-Object System.Windows.Forms.CheckBox
$chkCursor.Text = 'Cursor'
$chkCursor.Location = New-Object System.Drawing.Point(150, 130)
$chkCursor.Size = New-Object System.Drawing.Size(75, 23)
$chkCursor.Checked = $true
$settingsGroup.Controls.Add($chkCursor)

# Legacy compatibility flag for older settings. The live UI now uses the protocol-aware clock signaling selector.
$chkSendAbsoluteTimestamps = New-Object System.Windows.Forms.CheckBox
$chkSendAbsoluteTimestamps.Text = 'Legacy absolute timestamps'
$chkSendAbsoluteTimestamps.Location = New-Object System.Drawing.Point(235, 130)
$chkSendAbsoluteTimestamps.Size = New-Object System.Drawing.Size(220, 23)
$chkSendAbsoluteTimestamps.Checked = $false
$chkSendAbsoluteTimestamps.Visible = $false
$chkSendAbsoluteTimestamps.TabStop = $false
$settingsGroup.Controls.Add($chkSendAbsoluteTimestamps)

$lblTimingMode = Add-Label $settingsGroup 'WHIP clock signaling' 235 130 175
$cmbTimingMode = New-Object System.Windows.Forms.ComboBox
$cmbTimingMode.Location = New-Object System.Drawing.Point(415, 130)
$cmbTimingMode.Size = New-Object System.Drawing.Size(215, 23)
$cmbTimingMode.DropDownStyle = 'DropDownList'
$null = $cmbTimingMode.Items.AddRange([string[]]@(
    'Off / plugin default',
    'On / protocol clock signaling'
))
$cmbTimingMode.SelectedItem = $script:DefaultTimingMode
$settingsGroup.Controls.Add($cmbTimingMode)
$toolTip.SetToolTip($cmbTimingMode, 'One protocol-aware sink setting. WHIP and GST WebRTC emit do-clock-signalling=true when On; RTSP emits ntp-time-source=ntp. It does not alter upstream source, encoder, queue, or pipeline-clock properties.')

$chkSplitClockSignalingOverrides = New-Object System.Windows.Forms.CheckBox
$chkSplitClockSignalingOverrides.Text = 'Separate clock signaling per split pipeline'
$chkSplitClockSignalingOverrides.Location = New-Object System.Drawing.Point(15, 548)
$chkSplitClockSignalingOverrides.Size = New-Object System.Drawing.Size(300, 24)
$chkSplitClockSignalingOverrides.Checked = $script:DefaultSplitClockSignalingOverrides
$settingsGroup.Controls.Add($chkSplitClockSignalingOverrides)
$toolTip.SetToolTip($chkSplitClockSignalingOverrides, 'Physical split GST WebRTC only. Off makes both webrtcsink instances inherit the main WebRTC clock signaling setting. On exposes independent video-sink and audio-sink RFC7273 state.')

$cmbSplitVideoClockSignaling = New-Object System.Windows.Forms.ComboBox
$cmbSplitVideoClockSignaling.Location = New-Object System.Drawing.Point(15, 548)
$cmbSplitVideoClockSignaling.Size = New-Object System.Drawing.Size(215, 23)
$cmbSplitVideoClockSignaling.DropDownStyle = 'DropDownList'
$null = $cmbSplitVideoClockSignaling.Items.AddRange([string[]]@('Off / plugin default','RFC7273 NTP/PTP signaling'))
$cmbSplitVideoClockSignaling.SelectedItem = $script:DefaultSplitVideoClockSignaling
$settingsGroup.Controls.Add($cmbSplitVideoClockSignaling)
$toolTip.SetToolTip($cmbSplitVideoClockSignaling, 'Physical split mode video webrtcsink only. On emits do-clock-signalling=true on the video pipeline sink.')

$cmbSplitAudioClockSignaling = New-Object System.Windows.Forms.ComboBox
$cmbSplitAudioClockSignaling.Location = New-Object System.Drawing.Point(15, 548)
$cmbSplitAudioClockSignaling.Size = New-Object System.Drawing.Size(215, 23)
$cmbSplitAudioClockSignaling.DropDownStyle = 'DropDownList'
$null = $cmbSplitAudioClockSignaling.Items.AddRange([string[]]@('Off / plugin default','RFC7273 NTP/PTP signaling'))
$cmbSplitAudioClockSignaling.SelectedItem = $script:DefaultSplitAudioClockSignaling
$settingsGroup.Controls.Add($cmbSplitAudioClockSignaling)
$toolTip.SetToolTip($cmbSplitAudioClockSignaling, 'Physical split mode audio webrtcsink only. On emits do-clock-signalling=true on the audio pipeline sink.')

$lblTimestampStatus = New-Object System.Windows.Forms.Label
$lblTimestampStatus.Text = 'Timing: receiver/server timestamps'
$lblTimestampStatus.Location = New-Object System.Drawing.Point(580, 130)
$lblTimestampStatus.Size = New-Object System.Drawing.Size(215, 23)
$lblTimestampStatus.TextAlign = 'MiddleLeft'
$lblTimestampStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblTimestampStatus)

$lblDirectWebRtcStatus = New-Object System.Windows.Forms.Label
$lblDirectWebRtcStatus.Text = 'Direct WebRTC disabled'
$lblDirectWebRtcStatus.Location = New-Object System.Drawing.Point(15, 548)
$lblDirectWebRtcStatus.Size = New-Object System.Drawing.Size(535, 23)
$lblDirectWebRtcStatus.TextAlign = 'MiddleLeft'
$lblDirectWebRtcStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblDirectWebRtcStatus)

$txtDirectWebRtcSignalingHost = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcSignalingHost.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcSignalingHost.Size = New-Object System.Drawing.Size(155, 23)
$txtDirectWebRtcSignalingHost.Text = $script:DefaultDirectWebRtcSignalingHost
$settingsGroup.Controls.Add($txtDirectWebRtcSignalingHost)
$toolTip.SetToolTip($txtDirectWebRtcSignalingHost, 'Address used by GStreamer webrtcsink for its built-in signalling server. 0.0.0.0 listens on all local interfaces.')

$numDirectWebRtcSignalingPort = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcSignalingPort.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcSignalingPort.Size = New-Object System.Drawing.Size(85, 23)
$numDirectWebRtcSignalingPort.Minimum = 1
$numDirectWebRtcSignalingPort.Maximum = 65535
$numDirectWebRtcSignalingPort.Value = $script:DefaultDirectWebRtcSignalingPort
$settingsGroup.Controls.Add($numDirectWebRtcSignalingPort)
$toolTip.SetToolTip($numDirectWebRtcSignalingPort, 'TCP/WebSocket signalling port for webrtcsink. TCP/WebSocket signalling port. Default 8189 for proxy compatibility; media still negotiates separately through WebRTC ICE/UDP.')

$numDirectWebRtcSplitAudioSignalingPort = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcSplitAudioSignalingPort.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcSplitAudioSignalingPort.Size = New-Object System.Drawing.Size(85, 23)
$numDirectWebRtcSplitAudioSignalingPort.Minimum = 1
$numDirectWebRtcSplitAudioSignalingPort.Maximum = 65535
$numDirectWebRtcSplitAudioSignalingPort.Value = $script:DefaultDirectWebRtcSplitAudioSignalingPort
$settingsGroup.Controls.Add($numDirectWebRtcSplitAudioSignalingPort)
$toolTip.SetToolTip($numDirectWebRtcSplitAudioSignalingPort, 'TCP/WebSocket signalling port for the separate split-audio producer when shared signalling is off. Default 8190.')

$chkDirectWebRtcSharedSignaling = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcSharedSignaling.Text = 'Shared signalling for split A/V'
$chkDirectWebRtcSharedSignaling.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcSharedSignaling.Size = New-Object System.Drawing.Size(245, 24)
$chkDirectWebRtcSharedSignaling.Checked = $script:DefaultDirectWebRtcSharedSignaling
$settingsGroup.Controls.Add($chkDirectWebRtcSharedSignaling)
$toolTip.SetToolTip($chkDirectWebRtcSharedSignaling, 'Split mode only. Video owns the configured signalling server and the audio producer joins that same server through signaller::uri. Off preserves the existing separate-port method.')

$cmbDirectWebRtcMediaStreamGrouping = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcMediaStreamGrouping.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcMediaStreamGrouping.Size = New-Object System.Drawing.Size(315, 23)
$cmbDirectWebRtcMediaStreamGrouping.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcMediaStreamGrouping.Items.AddRange([string[]]@('Combined A/V MediaStream (default)','Separate audio/video MediaStreams (experimental)'))
$cmbDirectWebRtcMediaStreamGrouping.SelectedItem = $script:DefaultDirectWebRtcMediaStreamGrouping
$settingsGroup.Controls.Add($cmbDirectWebRtcMediaStreamGrouping)
$toolTip.SetToolTip($cmbDirectWebRtcMediaStreamGrouping, 'WHIP/GST WebRTC single-pipeline experiment. Separate mode rewrites the incoming SDP in the bundled player so Chromium receives video and audio under different MediaStream IDs. It preserves one producer, PeerConnection, ICE session, and gst-launch pipeline. Combined mode changes nothing.')

$txtDirectWebRtcVideoMediaStreamId = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcVideoMediaStreamId.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcVideoMediaStreamId.Size = New-Object System.Drawing.Size(180, 23)
$txtDirectWebRtcVideoMediaStreamId.Text = $script:DefaultDirectWebRtcVideoMediaStreamId
$settingsGroup.Controls.Add($txtDirectWebRtcVideoMediaStreamId)
$toolTip.SetToolTip($txtDirectWebRtcVideoMediaStreamId, 'MediaStream ID written into video a=msid SDP attributes when separate MediaStreams is enabled. The existing MediaStreamTrack ID is preserved.')

$txtDirectWebRtcAudioMediaStreamId = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcAudioMediaStreamId.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcAudioMediaStreamId.Size = New-Object System.Drawing.Size(180, 23)
$txtDirectWebRtcAudioMediaStreamId.Text = $script:DefaultDirectWebRtcAudioMediaStreamId
$settingsGroup.Controls.Add($txtDirectWebRtcAudioMediaStreamId)
$toolTip.SetToolTip($txtDirectWebRtcAudioMediaStreamId, 'MediaStream ID written into audio a=msid SDP attributes when separate MediaStreams is enabled. The existing MediaStreamTrack ID is preserved.')

$chkDirectWebRtcUnifiedPublisher = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcUnifiedPublisher.Text = 'Unified A/V producer via RTP bridge (experimental)'
$chkDirectWebRtcUnifiedPublisher.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcUnifiedPublisher.Size = New-Object System.Drawing.Size(355, 24)
$chkDirectWebRtcUnifiedPublisher.Checked = $script:DefaultDirectWebRtcUnifiedPublisher
$settingsGroup.Controls.Add($chkDirectWebRtcUnifiedPublisher)
$toolTip.SetToolTip($chkDirectWebRtcUnifiedPublisher, 'Split capture mode only. Launches independent video and audio capture pipelines into localhost RTP, then a third publisher pipeline exposes one WebRTC producer with video_0 and audio_0. Off preserves all existing split methods.')

$numDirectWebRtcBridgeVideoPort = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcBridgeVideoPort.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcBridgeVideoPort.Size = New-Object System.Drawing.Size(85, 23)
$numDirectWebRtcBridgeVideoPort.Minimum = 1
$numDirectWebRtcBridgeVideoPort.Maximum = 65535
$numDirectWebRtcBridgeVideoPort.Value = $script:DefaultDirectWebRtcBridgeVideoPort
$settingsGroup.Controls.Add($numDirectWebRtcBridgeVideoPort)
$toolTip.SetToolTip($numDirectWebRtcBridgeVideoPort, 'Localhost RTP bridge port carrying encoded video from the split video capture process to the unified WebRTC publisher.')

$numDirectWebRtcBridgeAudioPort = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcBridgeAudioPort.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcBridgeAudioPort.Size = New-Object System.Drawing.Size(85, 23)
$numDirectWebRtcBridgeAudioPort.Minimum = 1
$numDirectWebRtcBridgeAudioPort.Maximum = 65535
$numDirectWebRtcBridgeAudioPort.Value = $script:DefaultDirectWebRtcBridgeAudioPort
$settingsGroup.Controls.Add($numDirectWebRtcBridgeAudioPort)
$toolTip.SetToolTip($numDirectWebRtcBridgeAudioPort, 'Localhost RTP bridge port carrying Opus audio from the split audio capture process to the unified WebRTC publisher.')

$numDirectWebRtcBridgeJitterMs = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcBridgeJitterMs.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcBridgeJitterMs.Size = New-Object System.Drawing.Size(75, 23)
$numDirectWebRtcBridgeJitterMs.Minimum = 0
$numDirectWebRtcBridgeJitterMs.Maximum = 2000
$numDirectWebRtcBridgeJitterMs.Value = $script:DefaultDirectWebRtcBridgeJitterMs
$settingsGroup.Controls.Add($numDirectWebRtcBridgeJitterMs)
$toolTip.SetToolTip($numDirectWebRtcBridgeJitterMs, 'Optional RTP cadence reconstruction latency in the unified publisher for both localhost RTP legs. 0 disables and omits rtpjitterbuffer. Enabled buffers do not drop on latency.')

$numDirectWebRtcPublisherQueueMs = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcPublisherQueueMs.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcPublisherQueueMs.Size = New-Object System.Drawing.Size(75, 23)
$numDirectWebRtcPublisherQueueMs.Minimum = 0
$numDirectWebRtcPublisherQueueMs.Maximum = 2000
$numDirectWebRtcPublisherQueueMs.Value = $script:DefaultDirectWebRtcPublisherQueueMs
$settingsGroup.Controls.Add($numDirectWebRtcPublisherQueueMs)
$toolTip.SetToolTip($numDirectWebRtcPublisherQueueMs, 'Non-leaky time queue before each unified-publisher webrtcsink track. Satisfies the sink processing deadline and absorbs cross-process scheduling bursts. 0 disables and omits the queue.')

$chkDirectWebRtcAudioBridgePacing = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcAudioBridgePacing.Text = 'Pace localhost audio RTP from timestamps'
$chkDirectWebRtcAudioBridgePacing.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcAudioBridgePacing.Size = New-Object System.Drawing.Size(300, 24)
$chkDirectWebRtcAudioBridgePacing.Checked = $script:DefaultDirectWebRtcAudioBridgePacing
$settingsGroup.Controls.Add($chkDirectWebRtcAudioBridgePacing)
$toolTip.SetToolTip($chkDirectWebRtcAudioBridgePacing, 'Unified publisher only. sync=true on the audio bridge udpsink paces Opus RTP using the isolated audio pipeline clock instead of dumping packets immediately when its thread runs.')

$chkDirectWebRtcControlDataChannel = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcControlDataChannel.Text = 'Control data channel for upstream events'
$chkDirectWebRtcControlDataChannel.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcControlDataChannel.Size = New-Object System.Drawing.Size(310, 24)
$chkDirectWebRtcControlDataChannel.Checked = $script:DefaultDirectWebRtcControlDataChannel
$settingsGroup.Controls.Add($chkDirectWebRtcControlDataChannel)
$toolTip.SetToolTip($chkDirectWebRtcControlDataChannel, 'Unified publisher only. Emits enable-control-data-channel=true so arbitrary upstream events can be received through the WebRTC control channel. The localhost keyframe bridge still needs an explicit event relay.')

$cmbDirectWebRtcBundlePolicy = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcBundlePolicy.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcBundlePolicy.Size = New-Object System.Drawing.Size(145, 23)
$cmbDirectWebRtcBundlePolicy.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcBundlePolicy.Items.AddRange([string[]]@('Default','Max bundle'))
$cmbDirectWebRtcBundlePolicy.SelectedItem = $script:DefaultDirectWebRtcBundlePolicy
$settingsGroup.Controls.Add($cmbDirectWebRtcBundlePolicy)
$toolTip.SetToolTip($cmbDirectWebRtcBundlePolicy, 'Unified publisher only. Max bundle configures both the browser RTCPeerConnection and the dynamically created internal webrtcbin for one bundled transport. Selecting it activates the embedded unified-publisher host.')

$numDirectWebRtcInternalRtpMtu = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcInternalRtpMtu.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcInternalRtpMtu.Size = New-Object System.Drawing.Size(85, 23)
$numDirectWebRtcInternalRtpMtu.Minimum = 0
$numDirectWebRtcInternalRtpMtu.Maximum = 65535
$numDirectWebRtcInternalRtpMtu.Value = $script:DefaultDirectWebRtcInternalRtpMtu
$settingsGroup.Controls.Add($numDirectWebRtcInternalRtpMtu)
$toolTip.SetToolTip($numDirectWebRtcInternalRtpMtu, 'Unified publisher only. 0 leaves the final WebRTC RTP payloaders at plugin defaults. A nonzero value sets mtu on every dynamically created internal payloader through payloader-setup.')

$chkDirectWebRtcInternalRepeatHeaders = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcInternalRepeatHeaders.Text = 'Internal payloader repeat headers'
$chkDirectWebRtcInternalRepeatHeaders.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcInternalRepeatHeaders.Size = New-Object System.Drawing.Size(245, 24)
$chkDirectWebRtcInternalRepeatHeaders.Checked = $script:DefaultDirectWebRtcInternalRepeatHeaders
$settingsGroup.Controls.Add($chkDirectWebRtcInternalRepeatHeaders)
$toolTip.SetToolTip($chkDirectWebRtcInternalRepeatHeaders, 'Unified H.264/H.265 publisher only. Sets config-interval=-1 on the dynamically created final WebRTC video payloader so parameter sets repeat with each IDR. Off emits no internal override.')

$txtDirectWebRtcStun = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcStun.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcStun.Size = New-Object System.Drawing.Size(250, 23)
$txtDirectWebRtcStun.Text = $script:DefaultDirectWebRtcStunServer
$settingsGroup.Controls.Add($txtDirectWebRtcStun)
$toolTip.SetToolTip($txtDirectWebRtcStun, 'STUN server for Direct GStreamer WebRTC. Leave blank for no STUN.')

$chkDirectWebRtcTurnEnabled = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcTurnEnabled.Text = 'Enable TURN relay'
$chkDirectWebRtcTurnEnabled.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcTurnEnabled.Size = New-Object System.Drawing.Size(145, 24)
$chkDirectWebRtcTurnEnabled.Checked = $script:DefaultDirectWebRtcTurnEnabled
$settingsGroup.Controls.Add($chkDirectWebRtcTurnEnabled)
$toolTip.SetToolTip($chkDirectWebRtcTurnEnabled, 'Adds the TURN URI as a one-entry turn-servers array on rswebrtc sinks. TURN is opt-in because relayed media consumes third-party bandwidth and can add latency.')

$txtDirectWebRtcTurn = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcTurn.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcTurn.Size = New-Object System.Drawing.Size(330, 23)
$txtDirectWebRtcTurn.Text = $script:DefaultDirectWebRtcTurnServer
$settingsGroup.Controls.Add($txtDirectWebRtcTurn)
$toolTip.SetToolTip($txtDirectWebRtcTurn, 'TURN URI for Direct GST WebRTC and WHIP, for example turn://username:password@host:3478 or turns://username:password@host:5349. The public default address still requires valid credentials before it can relay media.')

$numDirectWebRtcMinRtpPort = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcMinRtpPort.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcMinRtpPort.Size = New-Object System.Drawing.Size(85, 23)
$numDirectWebRtcMinRtpPort.Minimum = 0
$numDirectWebRtcMinRtpPort.Maximum = 65535
$numDirectWebRtcMinRtpPort.Value = $script:DefaultDirectWebRtcMinRtpPort
$settingsGroup.Controls.Add($numDirectWebRtcMinRtpPort)
$toolTip.SetToolTip($numDirectWebRtcMinRtpPort, 'GST WebRTC protocol only. Lower bound of the ICE candidate UDP port range. Setting both min and max (nonzero) runs the pipeline in a dedicated native host process so the range can be enforced on each consumer''s ICE agent -- a real, verified property, just not reachable via a plain gst-launch property string. 0/0 uses the normal external gst-launch process with an unrestricted ephemeral range.')

$numDirectWebRtcMaxRtpPort = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcMaxRtpPort.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcMaxRtpPort.Size = New-Object System.Drawing.Size(85, 23)
$numDirectWebRtcMaxRtpPort.Minimum = 0
$numDirectWebRtcMaxRtpPort.Maximum = 65535
$numDirectWebRtcMaxRtpPort.Value = $script:DefaultDirectWebRtcMaxRtpPort
$settingsGroup.Controls.Add($numDirectWebRtcMaxRtpPort)
$toolTip.SetToolTip($numDirectWebRtcMaxRtpPort, 'GST WebRTC protocol only. Upper bound of the ICE candidate UDP port range. See the Min RTP port tooltip for how this is enforced.')

$chkUpnpEnabled = New-Object System.Windows.Forms.CheckBox
$chkUpnpEnabled.Text = 'Forward ports via UPnP (if router supports it)'
$chkUpnpEnabled.Location = New-Object System.Drawing.Point(15, 548)
$chkUpnpEnabled.Size = New-Object System.Drawing.Size(300, 24)
$chkUpnpEnabled.Checked = $script:DefaultUpnpEnabled
$settingsGroup.Controls.Add($chkUpnpEnabled)
$toolTip.SetToolTip($chkUpnpEnabled, 'Off by default. When enabled, asks the router for a UPnP IGD port mapping for whichever categories below are checked, so the stream is reachable from outside the LAN without manual router configuration. Best-effort only: if the router does not support UPnP the stream still starts normally over the existing STUN/TURN path. Mappings are removed when the stream stops.')

$lblUpnpStatus = New-Object System.Windows.Forms.Label
$lblUpnpStatus.Text = 'UPnP: disabled'
$lblUpnpStatus.Location = New-Object System.Drawing.Point(15, 548)
$lblUpnpStatus.Size = New-Object System.Drawing.Size(400, 23)
$lblUpnpStatus.TextAlign = 'MiddleLeft'
$lblUpnpStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblUpnpStatus)

$chkUpnpMapSignaling = New-Object System.Windows.Forms.CheckBox
$chkUpnpMapSignaling.Text = 'Map signalling port(s)'
$chkUpnpMapSignaling.Location = New-Object System.Drawing.Point(15, 548)
$chkUpnpMapSignaling.Size = New-Object System.Drawing.Size(180, 24)
$chkUpnpMapSignaling.Checked = $script:DefaultUpnpMapSignaling
$settingsGroup.Controls.Add($chkUpnpMapSignaling)
$toolTip.SetToolTip($chkUpnpMapSignaling, 'Include the video (and, if active, split-audio) signalling WebSocket port(s) in the UPnP mapping.')

$numUpnpSignalingExternalPort = New-Object System.Windows.Forms.NumericUpDown
$numUpnpSignalingExternalPort.Location = New-Object System.Drawing.Point(15, 548)
$numUpnpSignalingExternalPort.Size = New-Object System.Drawing.Size(90, 23)
$numUpnpSignalingExternalPort.Minimum = 0
$numUpnpSignalingExternalPort.Maximum = 65535
$numUpnpSignalingExternalPort.Value = $script:DefaultUpnpSignalingExternalPort
$settingsGroup.Controls.Add($numUpnpSignalingExternalPort)
$toolTip.SetToolTip($numUpnpSignalingExternalPort, 'External (WAN-side) port the router maps to the video signalling port above, e.g. 18189 -> 8189. 0 = map the same port number on both sides.')

$numUpnpSplitAudioExternalPort = New-Object System.Windows.Forms.NumericUpDown
$numUpnpSplitAudioExternalPort.Location = New-Object System.Drawing.Point(15, 548)
$numUpnpSplitAudioExternalPort.Size = New-Object System.Drawing.Size(90, 23)
$numUpnpSplitAudioExternalPort.Minimum = 0
$numUpnpSplitAudioExternalPort.Maximum = 65535
$numUpnpSplitAudioExternalPort.Value = $script:DefaultUpnpSplitAudioExternalPort
$settingsGroup.Controls.Add($numUpnpSplitAudioExternalPort)
$toolTip.SetToolTip($numUpnpSplitAudioExternalPort, 'External (WAN-side) port the router maps to the split-audio signalling port, when active. 0 = map the same port number on both sides.')

$chkUpnpMapRtp = New-Object System.Windows.Forms.CheckBox
$chkUpnpMapRtp.Text = 'Map RTP port range'
$chkUpnpMapRtp.Location = New-Object System.Drawing.Point(15, 548)
$chkUpnpMapRtp.Size = New-Object System.Drawing.Size(180, 24)
$chkUpnpMapRtp.Checked = $script:DefaultUpnpMapRtp
$settingsGroup.Controls.Add($chkUpnpMapRtp)
$toolTip.SetToolTip($chkUpnpMapRtp, 'Include the Min/Max RTP UDP port range in the UPnP mapping, when set. RTP ports are always mapped 1:1 (external port number == internal port number) -- remapping media ports is not offered, since the ICE agent itself only knows the internal port.')

$chkUpnpMapWebServer = New-Object System.Windows.Forms.CheckBox
$chkUpnpMapWebServer.Text = 'Map web viewer port'
$chkUpnpMapWebServer.Location = New-Object System.Drawing.Point(15, 548)
$chkUpnpMapWebServer.Size = New-Object System.Drawing.Size(180, 24)
$chkUpnpMapWebServer.Checked = $script:DefaultUpnpMapWebServer
$settingsGroup.Controls.Add($chkUpnpMapWebServer)
$toolTip.SetToolTip($chkUpnpMapWebServer, 'Include the web viewer HTTP port (from the Destination address, e.g. 8889) in the UPnP mapping.')

$numUpnpWebServerExternalPort = New-Object System.Windows.Forms.NumericUpDown
$numUpnpWebServerExternalPort.Location = New-Object System.Drawing.Point(15, 548)
$numUpnpWebServerExternalPort.Size = New-Object System.Drawing.Size(90, 23)
$numUpnpWebServerExternalPort.Minimum = 0
$numUpnpWebServerExternalPort.Maximum = 65535
$numUpnpWebServerExternalPort.Value = $script:DefaultUpnpWebServerExternalPort
$settingsGroup.Controls.Add($numUpnpWebServerExternalPort)
$toolTip.SetToolTip($numUpnpWebServerExternalPort, 'External (WAN-side) port the router maps to the web viewer port, e.g. 18889 -> 8889. 0 = map the same port number on both sides. A remote viewer must be given a URL using this external port explicitly; the page itself does not need to know about the remap.')

$chkDdnsEnabled = New-Object System.Windows.Forms.CheckBox
$chkDdnsEnabled.Text = 'Keep a hostname pointed at this stream (Dynamic DNS)'
$chkDdnsEnabled.Location = New-Object System.Drawing.Point(15, 548)
$chkDdnsEnabled.Size = New-Object System.Drawing.Size(340, 24)
$chkDdnsEnabled.Checked = $script:DefaultDdnsEnabled
$settingsGroup.Controls.Add($chkDdnsEnabled)
$toolTip.SetToolTip($chkDdnsEnabled, 'Off by default. When enabled, updates the DNS record below with the current public IPv4 address whenever the stream actually goes live. Best-effort only: a DDNS failure never blocks the stream from starting.')

$lblDdnsStatus = New-Object System.Windows.Forms.Label
$lblDdnsStatus.Text = 'DDNS: disabled'
$lblDdnsStatus.Location = New-Object System.Drawing.Point(15, 548)
$lblDdnsStatus.Size = New-Object System.Drawing.Size(460, 23)
$lblDdnsStatus.TextAlign = 'MiddleLeft'
$lblDdnsStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblDdnsStatus)

$cmbDdnsProvider = New-Object System.Windows.Forms.ComboBox
$cmbDdnsProvider.Location = New-Object System.Drawing.Point(15, 548)
$cmbDdnsProvider.Size = New-Object System.Drawing.Size(260, 23)
$cmbDdnsProvider.DropDownStyle = 'DropDownList'
$null = $cmbDdnsProvider.Items.AddRange([string[]]@('DuckDNS', 'No-IP / Dynu / FreeDNS (dyndns2)', 'Cloudflare', 'Custom URL'))
$cmbDdnsProvider.SelectedItem = $script:DefaultDdnsProvider
$settingsGroup.Controls.Add($cmbDdnsProvider)
$toolTip.SetToolTip($cmbDdnsProvider, 'Which Dynamic DNS provider to update. Only the fields relevant to the selected provider are enabled below.')

$txtDdnsHostname = New-Object System.Windows.Forms.TextBox
$txtDdnsHostname.Location = New-Object System.Drawing.Point(15, 548)
$txtDdnsHostname.Size = New-Object System.Drawing.Size(260, 23)
$txtDdnsHostname.Text = $script:DefaultDdnsHostname
$settingsGroup.Controls.Add($txtDdnsHostname)
$toolTip.SetToolTip($txtDdnsHostname, 'The hostname to keep current, e.g. myname.duckdns.org, myhost.ddns.net, or stream.example.com.')

$lblDdnsTokenCaption = Add-Label $settingsGroup 'Token' 15 548 90
$txtDdnsToken = New-Object System.Windows.Forms.TextBox
$txtDdnsToken.Location = New-Object System.Drawing.Point(15, 548)
$txtDdnsToken.Size = New-Object System.Drawing.Size(260, 23)
$txtDdnsToken.UseSystemPasswordChar = $true
$txtDdnsToken.Text = $script:DefaultDdnsToken
$settingsGroup.Controls.Add($txtDdnsToken)
$toolTip.SetToolTip($txtDdnsToken, 'DuckDNS: the token shown on your DuckDNS account page. Cloudflare: an API token scoped to Zone : DNS : Edit for the target zone. Shared between both providers since each only needs one secret token.')

$txtDdnsDynV2UpdateHost = New-Object System.Windows.Forms.TextBox
$txtDdnsDynV2UpdateHost.Location = New-Object System.Drawing.Point(15, 548)
$txtDdnsDynV2UpdateHost.Size = New-Object System.Drawing.Size(260, 23)
$txtDdnsDynV2UpdateHost.Text = $script:DefaultDdnsDynV2UpdateHost
$settingsGroup.Controls.Add($txtDdnsDynV2UpdateHost)
$toolTip.SetToolTip($txtDdnsDynV2UpdateHost, 'No-IP / Dynu / FreeDNS only. The update-protocol host: dynupdate.no-ip.com (No-IP), api.dynu.com (Dynu), or freedns.afraid.org (FreeDNS).')

$txtDdnsUsername = New-Object System.Windows.Forms.TextBox
$txtDdnsUsername.Location = New-Object System.Drawing.Point(15, 548)
$txtDdnsUsername.Size = New-Object System.Drawing.Size(260, 23)
$txtDdnsUsername.Text = $script:DefaultDdnsUsername
$settingsGroup.Controls.Add($txtDdnsUsername)
$toolTip.SetToolTip($txtDdnsUsername, 'No-IP / Dynu / FreeDNS: account username. Custom URL: optional HTTP Basic auth username (only sent if both username and password are set).')

$txtDdnsPassword = New-Object System.Windows.Forms.TextBox
$txtDdnsPassword.Location = New-Object System.Drawing.Point(15, 548)
$txtDdnsPassword.Size = New-Object System.Drawing.Size(260, 23)
$txtDdnsPassword.UseSystemPasswordChar = $true
$txtDdnsPassword.Text = $script:DefaultDdnsPassword
$settingsGroup.Controls.Add($txtDdnsPassword)
$toolTip.SetToolTip($txtDdnsPassword, 'No-IP / Dynu / FreeDNS: account password. Custom URL: optional HTTP Basic auth password (only sent if both username and password are set).')

$txtDdnsCloudflareZoneId = New-Object System.Windows.Forms.TextBox
$txtDdnsCloudflareZoneId.Location = New-Object System.Drawing.Point(15, 548)
$txtDdnsCloudflareZoneId.Size = New-Object System.Drawing.Size(260, 23)
$txtDdnsCloudflareZoneId.Text = $script:DefaultDdnsCloudflareZoneId
$settingsGroup.Controls.Add($txtDdnsCloudflareZoneId)
$toolTip.SetToolTip($txtDdnsCloudflareZoneId, 'Cloudflare only. The Zone ID from the domain''s Cloudflare dashboard overview page (right-hand "API" panel) -- NOT the Account ID shown just above it, a common mixup since both look like similar hex strings. The exact registered domain name (e.g. example.com) is also accepted and resolved to its Zone ID automatically. No record ID is needed -- the matching A record for the hostname above is looked up automatically, and created if it does not exist yet.')

$chkDdnsCloudflareProxied = New-Object System.Windows.Forms.CheckBox
$chkDdnsCloudflareProxied.Text = 'Proxy through Cloudflare (orange cloud)'
$chkDdnsCloudflareProxied.Location = New-Object System.Drawing.Point(15, 548)
$chkDdnsCloudflareProxied.Size = New-Object System.Drawing.Size(260, 24)
$chkDdnsCloudflareProxied.Checked = $script:DefaultDdnsCloudflareProxied
$settingsGroup.Controls.Add($chkDdnsCloudflareProxied)
$toolTip.SetToolTip($chkDdnsCloudflareProxied, 'Cloudflare only. Off by default. Cloudflare''s proxy only forwards plain HTTP/HTTPS, not arbitrary WebRTC/RTP ports, so this usually needs to stay off for the stream itself to remain reachable through the mapped ports.')

$txtDdnsCustomUrlTemplate = New-Object System.Windows.Forms.TextBox
$txtDdnsCustomUrlTemplate.Location = New-Object System.Drawing.Point(15, 548)
$txtDdnsCustomUrlTemplate.Size = New-Object System.Drawing.Size(400, 23)
$txtDdnsCustomUrlTemplate.Text = $script:DefaultDdnsCustomUrlTemplate
$settingsGroup.Controls.Add($txtDdnsCustomUrlTemplate)
$toolTip.SetToolTip($txtDdnsCustomUrlTemplate, 'Custom URL only. Any update URL, with {ip} and {hostname} substituted literally, e.g. https://example.com/update?host={hostname}&ip={ip}.')

$cmbDdnsCustomMethod = New-Object System.Windows.Forms.ComboBox
$cmbDdnsCustomMethod.Location = New-Object System.Drawing.Point(15, 548)
$cmbDdnsCustomMethod.Size = New-Object System.Drawing.Size(90, 23)
$cmbDdnsCustomMethod.DropDownStyle = 'DropDownList'
$null = $cmbDdnsCustomMethod.Items.AddRange([string[]]@('GET', 'PUT', 'POST'))
$cmbDdnsCustomMethod.SelectedItem = $script:DefaultDdnsCustomMethod
$settingsGroup.Controls.Add($cmbDdnsCustomMethod)
$toolTip.SetToolTip($cmbDdnsCustomMethod, 'Custom URL only. HTTP method used for the update request.')

$btnDdnsUpdateNow = New-Object System.Windows.Forms.Button
$btnDdnsUpdateNow.Text = 'Update DDNS Now'
$btnDdnsUpdateNow.Location = New-Object System.Drawing.Point(15, 548)
$btnDdnsUpdateNow.Size = New-Object System.Drawing.Size(150, 30)
$settingsGroup.Controls.Add($btnDdnsUpdateNow)
$toolTip.SetToolTip($btnDdnsUpdateNow, 'Resolves the current public IP and updates the configured DDNS record immediately, regardless of stream state -- useful for verifying credentials without going live.')

$chkLetsEncryptEnabled = New-Object System.Windows.Forms.CheckBox
$chkLetsEncryptEnabled.Text = "Get a Let's Encrypt certificate (DNS-01)"
$chkLetsEncryptEnabled.Location = New-Object System.Drawing.Point(15, 548)
$chkLetsEncryptEnabled.Size = New-Object System.Drawing.Size(300, 24)
$chkLetsEncryptEnabled.Checked = $script:DefaultLetsEncryptEnabled
$settingsGroup.Controls.Add($chkLetsEncryptEnabled)
$toolTip.SetToolTip($chkLetsEncryptEnabled, "Off by default. Requires Dynamic DNS above to be enabled with Cloudflare or DuckDNS as the provider (the only two that can publish the DNS-01 challenge record this needs). Issues/renews a Let's Encrypt certificate for the Dynamic DNS hostname; a failure never blocks the stream from starting.")

$lblLetsEncryptStatus = New-Object System.Windows.Forms.Label
$lblLetsEncryptStatus.Text = 'ACME: disabled'
$lblLetsEncryptStatus.Location = New-Object System.Drawing.Point(15, 548)
$lblLetsEncryptStatus.Size = New-Object System.Drawing.Size(460, 23)
$lblLetsEncryptStatus.TextAlign = 'MiddleLeft'
$lblLetsEncryptStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblLetsEncryptStatus)

$txtLetsEncryptEmail = New-Object System.Windows.Forms.TextBox
$txtLetsEncryptEmail.Location = New-Object System.Drawing.Point(15, 548)
$txtLetsEncryptEmail.Size = New-Object System.Drawing.Size(260, 23)
$txtLetsEncryptEmail.Text = $script:DefaultLetsEncryptEmail
$settingsGroup.Controls.Add($txtLetsEncryptEmail)
$toolTip.SetToolTip($txtLetsEncryptEmail, "Optional contact email for the Let's Encrypt account (expiry notices, etc.). Not required.")

$chkLetsEncryptStaging = New-Object System.Windows.Forms.CheckBox
$chkLetsEncryptStaging.Text = "Use Let's Encrypt staging environment"
$chkLetsEncryptStaging.Location = New-Object System.Drawing.Point(15, 548)
$chkLetsEncryptStaging.Size = New-Object System.Drawing.Size(260, 24)
$chkLetsEncryptStaging.Checked = $script:DefaultLetsEncryptStaging
$settingsGroup.Controls.Add($chkLetsEncryptStaging)
$toolTip.SetToolTip($chkLetsEncryptStaging, "On by default. Staging certificates aren't trusted by browsers but share none of production's tight rate limits (5 duplicate certs/week) -- verify the whole flow here first, then switch off once it works.")

$numLetsEncryptSignalingExternalPort = New-Object System.Windows.Forms.NumericUpDown
$numLetsEncryptSignalingExternalPort.Location = New-Object System.Drawing.Point(15, 548)
$numLetsEncryptSignalingExternalPort.Size = New-Object System.Drawing.Size(90, 23)
$numLetsEncryptSignalingExternalPort.Minimum = 0
$numLetsEncryptSignalingExternalPort.Maximum = 65535
$numLetsEncryptSignalingExternalPort.Value = $script:DefaultLetsEncryptSignalingExternalPort
$settingsGroup.Controls.Add($numLetsEncryptSignalingExternalPort)
$toolTip.SetToolTip($numLetsEncryptSignalingExternalPort, 'External (WAN-side) HTTPS/WSS port for video signalling once TLS termination is wired in. 0 = same as the internal signalling port.')

$numLetsEncryptSplitAudioExternalPort = New-Object System.Windows.Forms.NumericUpDown
$numLetsEncryptSplitAudioExternalPort.Location = New-Object System.Drawing.Point(15, 548)
$numLetsEncryptSplitAudioExternalPort.Size = New-Object System.Drawing.Size(90, 23)
$numLetsEncryptSplitAudioExternalPort.Minimum = 0
$numLetsEncryptSplitAudioExternalPort.Maximum = 65535
$numLetsEncryptSplitAudioExternalPort.Value = $script:DefaultLetsEncryptSplitAudioExternalPort
$settingsGroup.Controls.Add($numLetsEncryptSplitAudioExternalPort)
$toolTip.SetToolTip($numLetsEncryptSplitAudioExternalPort, 'External (WAN-side) HTTPS/WSS port for split-audio signalling, when active. 0 = same as the internal port.')

$numLetsEncryptWebServerExternalPort = New-Object System.Windows.Forms.NumericUpDown
$numLetsEncryptWebServerExternalPort.Location = New-Object System.Drawing.Point(15, 548)
$numLetsEncryptWebServerExternalPort.Size = New-Object System.Drawing.Size(90, 23)
$numLetsEncryptWebServerExternalPort.Minimum = 0
$numLetsEncryptWebServerExternalPort.Maximum = 65535
$numLetsEncryptWebServerExternalPort.Value = $script:DefaultLetsEncryptWebServerExternalPort
$settingsGroup.Controls.Add($numLetsEncryptWebServerExternalPort)
$toolTip.SetToolTip($numLetsEncryptWebServerExternalPort, 'External (WAN-side) HTTPS port for the web viewer once TLS termination is wired in. 0 = same as the internal port.')

$btnLetsEncryptIssueNow = New-Object System.Windows.Forms.Button
$btnLetsEncryptIssueNow.Text = 'Issue/Renew Now'
$btnLetsEncryptIssueNow.Location = New-Object System.Drawing.Point(15, 548)
$btnLetsEncryptIssueNow.Size = New-Object System.Drawing.Size(150, 30)
$settingsGroup.Controls.Add($btnLetsEncryptIssueNow)
$toolTip.SetToolTip($btnLetsEncryptIssueNow, "Runs the ACME DNS-01 flow immediately, regardless of stream state -- useful for verifying this against Let's Encrypt staging before going live with it.")

$chkViewerAuthenticationEnabled = New-Object System.Windows.Forms.CheckBox
$chkViewerAuthenticationEnabled.Text = 'Require viewer login for HTTPS/WSS'
$chkViewerAuthenticationEnabled.Location = New-Object System.Drawing.Point(15, 548)
$chkViewerAuthenticationEnabled.Size = New-Object System.Drawing.Size(300, 24)
$chkViewerAuthenticationEnabled.Checked = $script:DefaultViewerAuthenticationEnabled
$settingsGroup.Controls.Add($chkViewerAuthenticationEnabled)
$toolTip.SetToolTip($chkViewerAuthenticationEnabled, 'Protects the viewer page and every signaling WebSocket at the built-in TLS edge. Requires an active Let''s Encrypt certificate; unencrypted HTTP/WS is never used for authenticated viewing.')

$lstViewerAuthenticationAccounts = New-Object System.Windows.Forms.ListBox
$lstViewerAuthenticationAccounts.Location = New-Object System.Drawing.Point(15, 548)
$lstViewerAuthenticationAccounts.Size = New-Object System.Drawing.Size(260, 82)
$lstViewerAuthenticationAccounts.SelectionMode = 'One'
$settingsGroup.Controls.Add($lstViewerAuthenticationAccounts)
$toolTip.SetToolTip($lstViewerAuthenticationAccounts, 'Each named account can sign in independently -- logging out or removing one account never affects any other viewer''s session.')

$txtViewerAuthenticationNewUsername = New-Object System.Windows.Forms.TextBox
$txtViewerAuthenticationNewUsername.Location = New-Object System.Drawing.Point(15, 548)
$txtViewerAuthenticationNewUsername.Size = New-Object System.Drawing.Size(180, 23)
$settingsGroup.Controls.Add($txtViewerAuthenticationNewUsername)
$toolTip.SetToolTip($txtViewerAuthenticationNewUsername, 'Username for a new viewer account.')

$txtViewerAuthenticationNewPassword = New-Object System.Windows.Forms.TextBox
$txtViewerAuthenticationNewPassword.Location = New-Object System.Drawing.Point(15, 548)
$txtViewerAuthenticationNewPassword.Size = New-Object System.Drawing.Size(180, 23)
$txtViewerAuthenticationNewPassword.UseSystemPasswordChar = $true
$settingsGroup.Controls.Add($txtViewerAuthenticationNewPassword)
$toolTip.SetToolTip($txtViewerAuthenticationNewPassword, 'Password for the new account (10-256 characters). The plaintext is never saved; Glass stores a salted PBKDF2-HMAC-SHA256 hash.')

$btnViewerAuthenticationAddAccount = New-Object System.Windows.Forms.Button
$btnViewerAuthenticationAddAccount.Text = 'Add account'
$btnViewerAuthenticationAddAccount.Location = New-Object System.Drawing.Point(15, 548)
$btnViewerAuthenticationAddAccount.Size = New-Object System.Drawing.Size(120, 27)
$settingsGroup.Controls.Add($btnViewerAuthenticationAddAccount)
$toolTip.SetToolTip($btnViewerAuthenticationAddAccount, 'Adds (or replaces the password for) the account above.')

$btnViewerAuthenticationRemoveAccount = New-Object System.Windows.Forms.Button
$btnViewerAuthenticationRemoveAccount.Text = 'Remove selected'
$btnViewerAuthenticationRemoveAccount.Location = New-Object System.Drawing.Point(15, 548)
$btnViewerAuthenticationRemoveAccount.Size = New-Object System.Drawing.Size(120, 27)
$settingsGroup.Controls.Add($btnViewerAuthenticationRemoveAccount)
$toolTip.SetToolTip($btnViewerAuthenticationRemoveAccount, 'Removes the selected account and immediately revokes any of its active sessions.')

$btnViewerAuthenticationEnableTotp = New-Object System.Windows.Forms.Button
$btnViewerAuthenticationEnableTotp.Text = 'Set up 2FA'
$btnViewerAuthenticationEnableTotp.Location = New-Object System.Drawing.Point(15, 548)
$btnViewerAuthenticationEnableTotp.Size = New-Object System.Drawing.Size(120, 27)
$settingsGroup.Controls.Add($btnViewerAuthenticationEnableTotp)
$toolTip.SetToolTip($btnViewerAuthenticationEnableTotp, 'Adds a TOTP authenticator-app code requirement to the selected account, after confirming the current code.')

$btnViewerAuthenticationDisableTotp = New-Object System.Windows.Forms.Button
$btnViewerAuthenticationDisableTotp.Text = 'Disable 2FA'
$btnViewerAuthenticationDisableTotp.Location = New-Object System.Drawing.Point(15, 548)
$btnViewerAuthenticationDisableTotp.Size = New-Object System.Drawing.Size(120, 27)
$settingsGroup.Controls.Add($btnViewerAuthenticationDisableTotp)
$toolTip.SetToolTip($btnViewerAuthenticationDisableTotp, 'Removes the authenticator-app code requirement from the selected account.')

$numViewerAuthenticationSessionHours = New-Object System.Windows.Forms.NumericUpDown
$numViewerAuthenticationSessionHours.Location = New-Object System.Drawing.Point(15, 548)
$numViewerAuthenticationSessionHours.Size = New-Object System.Drawing.Size(90, 23)
$numViewerAuthenticationSessionHours.Minimum = 1
$numViewerAuthenticationSessionHours.Maximum = 168
$numViewerAuthenticationSessionHours.Value = $script:DefaultViewerAuthenticationSessionHours
$settingsGroup.Controls.Add($numViewerAuthenticationSessionHours)
$toolTip.SetToolTip($numViewerAuthenticationSessionHours, 'How long an authenticated viewer session remains valid. Sessions are also invalidated whenever the TLS proxies restart.')

$txtDirectWebRtcWebPath = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcWebPath.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcWebPath.Size = New-Object System.Drawing.Size(120, 23)
$txtDirectWebRtcWebPath.Text = $script:DefaultDirectWebRtcWebPath
$settingsGroup.Controls.Add($txtDirectWebRtcWebPath)
$toolTip.SetToolTip($txtDirectWebRtcWebPath, 'Path where GStreamer should serve the WebRTC viewer. Example: /live makes the viewer URL http://127.0.0.1:8889/live/')

$txtDirectWebRtcWebDirectory = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcWebDirectory.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcWebDirectory.Size = New-Object System.Drawing.Size(260, 23)
$txtDirectWebRtcWebDirectory.Text = $script:DefaultDirectWebRtcWorkingWebDirectory
$settingsGroup.Controls.Add($txtDirectWebRtcWebDirectory)
$toolTip.SetToolTip($txtDirectWebRtcWebDirectory, 'Optional gstwebrtc-api/dist directory for the built-in webrtcsink web UI. If blank, GStreamer Glass searches common install paths. Missing assets usually means the web port answers but returns 404.')

$btnBrowseDirectWebRtcWebDirectory = New-Object System.Windows.Forms.Button
$btnBrowseDirectWebRtcWebDirectory.Text = 'Browse working'
$btnBrowseDirectWebRtcWebDirectory.Location = New-Object System.Drawing.Point(15, 548)
$btnBrowseDirectWebRtcWebDirectory.Size = New-Object System.Drawing.Size(80, 27)
$settingsGroup.Controls.Add($btnBrowseDirectWebRtcWebDirectory)
$toolTip.SetToolTip($btnBrowseDirectWebRtcWebDirectory, 'Select the gstwebrtc-api/dist folder used by webrtcsink run-web-server.')

$btnDetectDirectWebRtcWebDirectory = New-Object System.Windows.Forms.Button
$btnDetectDirectWebRtcWebDirectory.Text = 'Detect working'
$btnDetectDirectWebRtcWebDirectory.Location = New-Object System.Drawing.Point(15, 548)
$btnDetectDirectWebRtcWebDirectory.Size = New-Object System.Drawing.Size(80, 27)
$settingsGroup.Controls.Add($btnDetectDirectWebRtcWebDirectory)
$toolTip.SetToolTip($btnDetectDirectWebRtcWebDirectory, 'Detect/create the writable working web UI folder. This is the folder actually served by webrtcsink.')

$cmbDirectWebRtcBundledWebMode = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcBundledWebMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcBundledWebMode.Size = New-Object System.Drawing.Size(180, 23)
$cmbDirectWebRtcBundledWebMode.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcBundledWebMode.Items.AddRange([string[]]@('Auto-detect beside EXE','Manual path'))
$cmbDirectWebRtcBundledWebMode.SelectedItem = $script:DefaultDirectWebRtcBundledWebMode
$settingsGroup.Controls.Add($cmbDirectWebRtcBundledWebMode)
$toolTip.SetToolTip($cmbDirectWebRtcBundledWebMode, 'Bundled static web UI source. Auto finds gstwebrtc-api\dist beside GStreamer Glass.exe / the source script. Manual is for dev or custom installs.')

$txtDirectWebRtcBundledWebDirectory = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcBundledWebDirectory.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcBundledWebDirectory.Size = New-Object System.Drawing.Size(300, 23)
$txtDirectWebRtcBundledWebDirectory.Text = $script:DefaultDirectWebRtcBundledWebDirectory
$settingsGroup.Controls.Add($txtDirectWebRtcBundledWebDirectory)
$toolTip.SetToolTip($txtDirectWebRtcBundledWebDirectory, 'Bundled gstwebrtc-api\dist folder. Usually beside the EXE. Must contain index.html and player.js.')

$btnBrowseDirectWebRtcBundledWebDirectory = New-Object System.Windows.Forms.Button
$btnBrowseDirectWebRtcBundledWebDirectory.Text = 'Browse source'
$btnBrowseDirectWebRtcBundledWebDirectory.Location = New-Object System.Drawing.Point(15, 548)
$btnBrowseDirectWebRtcBundledWebDirectory.Size = New-Object System.Drawing.Size(100, 27)
$settingsGroup.Controls.Add($btnBrowseDirectWebRtcBundledWebDirectory)
$toolTip.SetToolTip($btnBrowseDirectWebRtcBundledWebDirectory, 'Select the bundled/static gstwebrtc-api\dist source folder.')

$btnDetectDirectWebRtcBundledWebDirectory = New-Object System.Windows.Forms.Button
$btnDetectDirectWebRtcBundledWebDirectory.Text = 'Detect source'
$btnDetectDirectWebRtcBundledWebDirectory.Location = New-Object System.Drawing.Point(15, 548)
$btnDetectDirectWebRtcBundledWebDirectory.Size = New-Object System.Drawing.Size(100, 27)
$settingsGroup.Controls.Add($btnDetectDirectWebRtcBundledWebDirectory)
$toolTip.SetToolTip($btnDetectDirectWebRtcBundledWebDirectory, 'Detect the bundled/static web UI source folder beside the app/script.')

$cmbDirectWebRtcWorkingWebMode = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcWorkingWebMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcWorkingWebMode.Size = New-Object System.Drawing.Size(160, 23)
$cmbDirectWebRtcWorkingWebMode.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcWorkingWebMode.Items.AddRange([string[]]@('Auto: LocalAppData','Manual path'))
$cmbDirectWebRtcWorkingWebMode.SelectedItem = $script:DefaultDirectWebRtcWorkingWebMode
$settingsGroup.Controls.Add($cmbDirectWebRtcWorkingWebMode)
$toolTip.SetToolTip($cmbDirectWebRtcWorkingWebMode, 'Working/served web UI directory. Auto uses %%LOCALAPPDATA%%\GStreamerGlass so no admin rights are needed.')


$cmbDirectWebRtcCongestion = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcCongestion.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcCongestion.Size = New-Object System.Drawing.Size(110, 23)
$cmbDirectWebRtcCongestion.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcCongestion.Items.AddRange([string[]]@('gcc','homegrown','disabled'))
$cmbDirectWebRtcCongestion.SelectedItem = 'disabled'
$settingsGroup.Controls.Add($cmbDirectWebRtcCongestion)
$toolTip.SetToolTip($cmbDirectWebRtcCongestion, 'WebRTC bitrate adaptation for WHIP/GST WebRTC. Disabled/fixed bitrate is the sane debug default; gcc can create rubber-band behavior while adapting.')

$numDirectWebRtcStartBitrateKbps = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcStartBitrateKbps.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcStartBitrateKbps.Size = New-Object System.Drawing.Size(95, 23)
$numDirectWebRtcStartBitrateKbps.Minimum = 0
$numDirectWebRtcStartBitrateKbps.Maximum = 1000000
$numDirectWebRtcStartBitrateKbps.Increment = 500
$numDirectWebRtcStartBitrateKbps.Value = $script:DefaultDirectWebRtcStartBitrateKbps
$settingsGroup.Controls.Add($numDirectWebRtcStartBitrateKbps)
$toolTip.SetToolTip($numDirectWebRtcStartBitrateKbps, 'WebRTC/Signaling layer only (webrtcsink start-bitrate) -- NOT the encoder. 0 = follow Encoder bitrate kbps. A nonzero value here overrides that exactly, unclamped, independently of the encoder''s actual bitrate.')

$numDirectWebRtcMinBitrateKbps = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcMinBitrateKbps.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcMinBitrateKbps.Size = New-Object System.Drawing.Size(95, 23)
$numDirectWebRtcMinBitrateKbps.Minimum = 0
$numDirectWebRtcMinBitrateKbps.Maximum = 1000000
$numDirectWebRtcMinBitrateKbps.Increment = 500
$numDirectWebRtcMinBitrateKbps.Value = $script:DefaultDirectWebRtcMinBitrateKbps
$settingsGroup.Controls.Add($numDirectWebRtcMinBitrateKbps)
$toolTip.SetToolTip($numDirectWebRtcMinBitrateKbps, 'WebRTC/Signaling layer only (webrtcsink min-bitrate) -- NOT the encoder. 0 = derive from the Smooth profile dropdown as before. A nonzero value here overrides the Smooth profile calculation exactly, unclamped, for testing.')

$cmbDirectWebRtcMitigation = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcMitigation.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcMitigation.Size = New-Object System.Drawing.Size(150, 23)
$cmbDirectWebRtcMitigation.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcMitigation.Items.AddRange([string[]]@('none','downscaled','downsampled','downsampled+downscaled'))
$cmbDirectWebRtcMitigation.SelectedItem = 'none'
$settingsGroup.Controls.Add($cmbDirectWebRtcMitigation)
$toolTip.SetToolTip($cmbDirectWebRtcMitigation, 'Allows webrtcsink to lower resolution and/or framerate under congestion. Use none for deterministic low-latency LAN tests.')

$chkDirectWebRtcFec = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcFec.Text = 'FEC'
$chkDirectWebRtcFec.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcFec.Size = New-Object System.Drawing.Size(70, 24)
$chkDirectWebRtcFec.Checked = $false
$settingsGroup.Controls.Add($chkDirectWebRtcFec)
$toolTip.SetToolTip($chkDirectWebRtcFec, 'Forward error correction. Can help loss, but may add overhead.')

$chkDirectWebRtcRetransmission = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcRetransmission.Text = 'Retransmit'
$chkDirectWebRtcRetransmission.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcRetransmission.Size = New-Object System.Drawing.Size(110, 24)
$chkDirectWebRtcRetransmission.Checked = $false
$settingsGroup.Controls.Add($chkDirectWebRtcRetransmission)
$toolTip.SetToolTip($chkDirectWebRtcRetransmission, 'Allow WebRTC retransmission requests. Disable only for brutal LAN latency experiments.')

$chkDirectWebRtcFec.Visible = $false
$chkDirectWebRtcRetransmission.Visible = $false

$lblWebRtcRecoveryMode = Add-Label $settingsGroup 'Recovery' 15 548 80

$cmbWebRtcRecoveryMode = New-Object System.Windows.Forms.ComboBox
$cmbWebRtcRecoveryMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbWebRtcRecoveryMode.Size = New-Object System.Drawing.Size(135, 23)
$cmbWebRtcRecoveryMode.DropDownStyle = 'DropDownList'
$null = $cmbWebRtcRecoveryMode.Items.AddRange([string[]]@('None','RTX only','FEC only','FEC + RTX'))
$cmbWebRtcRecoveryMode.SelectedItem = $script:DefaultWebRtcRecoveryMode
$settingsGroup.Controls.Add($cmbWebRtcRecoveryMode)
$toolTip.SetToolTip($cmbWebRtcRecoveryMode, 'WebRTC recovery mode for WHIP and GST WebRTC. None is the cleanest sane default. RTX can help loss but can add bursts; FEC can add overhead and visible stutter on low-latency desktop streams.')

$lblWebRtcSenderQueueMode = Add-Label $settingsGroup 'Encoded sender queue' 15 548 125

$cmbWebRtcSenderQueueMode = New-Object System.Windows.Forms.ComboBox
$cmbWebRtcSenderQueueMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbWebRtcSenderQueueMode.Size = New-Object System.Drawing.Size(165, 23)
$cmbWebRtcSenderQueueMode.DropDownStyle = 'DropDownList'
$null = $cmbWebRtcSenderQueueMode.Items.AddRange([string[]]@('Leaky live','Small cushion','Non-leaky experimental'))
$cmbWebRtcSenderQueueMode.SelectedItem = $script:DefaultWebRtcSenderQueueMode
$settingsGroup.Controls.Add($cmbWebRtcSenderQueueMode)
$toolTip.SetToolTip($cmbWebRtcSenderQueueMode, 'Encoded-video queue behavior for WHIP and GST WebRTC. Leaky live drops late frames instead of rubber-banding. Non-leaky is diagnostic only.')

$lblDirectWebRtcSmoothnessProfile = Add-Label $settingsGroup 'Smooth profile' 15 548 100

$cmbDirectWebRtcSmoothnessProfile = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcSmoothnessProfile.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcSmoothnessProfile.Size = New-Object System.Drawing.Size(150, 23)
$cmbDirectWebRtcSmoothnessProfile.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcSmoothnessProfile.Items.AddRange([string[]]@('Sane defaults','Lowest latency','Balanced smooth','WAN smooth','Adaptive viewer','Custom'))
$cmbDirectWebRtcSmoothnessProfile.SelectedItem = $script:DefaultDirectWebRtcSmoothnessProfile
$settingsGroup.Controls.Add($cmbDirectWebRtcSmoothnessProfile)
$toolTip.SetToolTip($cmbDirectWebRtcSmoothnessProfile, 'Direct GST WebRTC smoothing preset. Balanced smooth adds a tiny sender pacing queue and receiver jitter target. WAN smooth adds more cushion. Adaptive viewer lets the bundled browser player raise/lower jitter target from WebRTC stats.')

$lblDirectWebRtcPacingMs = Add-Label $settingsGroup 'Queue cap ms (0=off)' 15 548 140

$numDirectWebRtcPacingMs = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcPacingMs.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcPacingMs.Size = New-Object System.Drawing.Size(70, 23)
$numDirectWebRtcPacingMs.Minimum = 0
$numDirectWebRtcPacingMs.Maximum = 500
$numDirectWebRtcPacingMs.Increment = 10
$numDirectWebRtcPacingMs.Value = $script:DefaultDirectWebRtcPacingMs
$settingsGroup.Controls.Add($numDirectWebRtcPacingMs)
$toolTip.SetToolTip($numDirectWebRtcPacingMs, 'Encoded-video sender queue max-size-time for WHIP/GST WebRTC. 0 always emits max-size-time=0 with no hidden fallback. This is not the browser JBUF target; high values can accumulate latency.')

$lblDirectWebRtcPlayerJitterMs = Add-Label $settingsGroup 'Audio JBUF ms' 15 548 130

$numDirectWebRtcPlayerJitterMs = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcPlayerJitterMs.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcPlayerJitterMs.Size = New-Object System.Drawing.Size(70, 23)
$numDirectWebRtcPlayerJitterMs.Minimum = 0
$numDirectWebRtcPlayerJitterMs.Maximum = 500
$numDirectWebRtcPlayerJitterMs.Increment = 10
$numDirectWebRtcPlayerJitterMs.Value = $script:DefaultDirectWebRtcPlayerJitterMs
$settingsGroup.Controls.Add($numDirectWebRtcPlayerJitterMs)
$toolTip.SetToolTip($numDirectWebRtcPlayerJitterMs, 'Chrome receiver jitterBufferTarget for the bundled GST WebRTC audio receiver, in milliseconds. 0 disables the override.')

$lblDirectWebRtcVideoJitterMs = Add-Label $settingsGroup 'Video JBUF ms' 15 548 130

$numDirectWebRtcVideoJitterMs = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcVideoJitterMs.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcVideoJitterMs.Size = New-Object System.Drawing.Size(70, 23)
$numDirectWebRtcVideoJitterMs.Minimum = 0
$numDirectWebRtcVideoJitterMs.Maximum = 500
$numDirectWebRtcVideoJitterMs.Increment = 5
$numDirectWebRtcVideoJitterMs.Value = $script:DefaultDirectWebRtcVideoJitterMs
$settingsGroup.Controls.Add($numDirectWebRtcVideoJitterMs)
$toolTip.SetToolTip($numDirectWebRtcVideoJitterMs, 'Chrome receiver jitterBufferTarget for the bundled GST WebRTC video receiver, in milliseconds. 0 disables the override.')

$btnOpenDirectWebRtcViewer = New-Object System.Windows.Forms.Button
$btnOpenDirectWebRtcViewer.Text = 'Open viewer'
$btnOpenDirectWebRtcViewer.Location = New-Object System.Drawing.Point(15, 548)
$btnOpenDirectWebRtcViewer.Size = New-Object System.Drawing.Size(100, 28)
$settingsGroup.Controls.Add($btnOpenDirectWebRtcViewer)
$toolTip.SetToolTip($btnOpenDirectWebRtcViewer, 'Open the Direct GStreamer WebRTC web viewer URL in your default browser.')

$btnCopyDirectWebRtcViewer = New-Object System.Windows.Forms.Button
$btnCopyDirectWebRtcViewer.Text = 'Copy URL'
$btnCopyDirectWebRtcViewer.Location = New-Object System.Drawing.Point(15, 548)
$btnCopyDirectWebRtcViewer.Size = New-Object System.Drawing.Size(90, 28)
$settingsGroup.Controls.Add($btnCopyDirectWebRtcViewer)
$toolTip.SetToolTip($btnCopyDirectWebRtcViewer, 'Copy the Direct GStreamer WebRTC local viewer URL.')

$btnRefreshDirectWebRtcWebUi = New-Object System.Windows.Forms.Button
$btnRefreshDirectWebRtcWebUi.Text = 'Force refresh UI'
$btnRefreshDirectWebRtcWebUi.Location = New-Object System.Drawing.Point(15, 548)
$btnRefreshDirectWebRtcWebUi.Size = New-Object System.Drawing.Size(120, 28)
$settingsGroup.Controls.Add($btnRefreshDirectWebRtcWebUi)
$toolTip.SetToolTip($btnRefreshDirectWebRtcWebUi, 'Force-copy versioned static web player assets from bundled source to the writable working dir, excluding runtime gstglass-config.js, then rewrite config from Player tab values.')

$btnOpenDirectWebRtcServedDir = New-Object System.Windows.Forms.Button
$btnOpenDirectWebRtcServedDir.Text = 'Open served dir'
$btnOpenDirectWebRtcServedDir.Location = New-Object System.Drawing.Point(15, 548)
$btnOpenDirectWebRtcServedDir.Size = New-Object System.Drawing.Size(120, 28)
$settingsGroup.Controls.Add($btnOpenDirectWebRtcServedDir)
$toolTip.SetToolTip($btnOpenDirectWebRtcServedDir, 'Open the writable working/served web UI folder under LocalAppData or your manual path.')

$btnOpenDirectWebRtcBundledDir = New-Object System.Windows.Forms.Button
$btnOpenDirectWebRtcBundledDir.Text = 'Open bundled dir'
$btnOpenDirectWebRtcBundledDir.Location = New-Object System.Drawing.Point(15, 548)
$btnOpenDirectWebRtcBundledDir.Size = New-Object System.Drawing.Size(120, 28)
$settingsGroup.Controls.Add($btnOpenDirectWebRtcBundledDir)
$toolTip.SetToolTip($btnOpenDirectWebRtcBundledDir, 'Open the bundled gstwebrtc-api/dist folder shipped beside this script/app.')

$lblDirectWebRtcWebUiStatus = Add-Label $settingsGroup 'Web UI status: not checked' 15 548 520

$chkPreview = New-Object System.Windows.Forms.CheckBox
$chkPreview.Text = 'Show Preview'
$chkPreview.Location = New-Object System.Drawing.Point(235, 130)
$chkPreview.Size = New-Object System.Drawing.Size(80, 23)
$chkPreview.Checked = $false
$settingsGroup.Controls.Add($chkPreview)
$toolTip.SetToolTip($chkPreview, 'Enables standalone preview while stopped and, unless Hide preview during stream is enabled, includes a local preview branch when the stream starts.')

$chkHidePreviewDuringStream = New-Object System.Windows.Forms.CheckBox
$chkHidePreviewDuringStream.Text = 'Hide preview during stream'
$chkHidePreviewDuringStream.AutoSize = $true
$chkHidePreviewDuringStream.Checked = $false
$settingsGroup.Controls.Add($chkHidePreviewDuringStream)
$toolTip.SetToolTip($chkHidePreviewDuringStream, 'When enabled, Show Preview is used while stopped, but live video is hidden in both the main Preview card and Scenes canvas. Scene drag/resize controls remain available for live editing.')

$chkAutoRestart = New-Object System.Windows.Forms.CheckBox
$chkAutoRestart.Text = 'Auto-restart on exit'
$chkAutoRestart.Location = New-Object System.Drawing.Point(325, 130)
$chkAutoRestart.Size = New-Object System.Drawing.Size(145, 23)
$chkAutoRestart.Checked = $true
$settingsGroup.Controls.Add($chkAutoRestart)

$chkVerbose = New-Object System.Windows.Forms.CheckBox
$chkVerbose.Text = 'Verbose output'
$chkVerbose.Location = New-Object System.Drawing.Point(480, 130)
$chkVerbose.Size = New-Object System.Drawing.Size(120, 23)
$chkVerbose.Checked = $false
$settingsGroup.Controls.Add($chkVerbose)
$toolTip.SetToolTip($chkVerbose, 'Adds gst-launch -v. This is element/caps verbosity, not full GST_DEBUG logging. Use GST debug below for deep logs.')

$chkDiskProcessLogging = New-Object System.Windows.Forms.CheckBox
$chkDiskProcessLogging.Text = 'Write process logs to disk'
$chkDiskProcessLogging.Location = New-Object System.Drawing.Point(480, 158)
$chkDiskProcessLogging.Size = New-Object System.Drawing.Size(190, 23)
$chkDiskProcessLogging.Checked = $script:DefaultDiskProcessLogging
$settingsGroup.Controls.Add($chkDiskProcessLogging)
$toolTip.SetToolTip($chkDiskProcessLogging, 'Off by default. When off, gst-launch/MediaMTX stdout/stderr are not redirected to per-run log files. GST debug or tracer options still explicitly enable diagnostic process logs for that run. Verbose output does not -- it only adds gst-launch -v and never forces disk logging by itself.')

$chkPsDebug = New-Object System.Windows.Forms.CheckBox
$chkPsDebug.Text = 'PowerShell debugging'
$chkPsDebug.Location = New-Object System.Drawing.Point(480, 186)
$chkPsDebug.Size = New-Object System.Drawing.Size(170, 23)
$chkPsDebug.Checked = $script:DefaultPsDebugEnabled
$settingsGroup.Controls.Add($chkPsDebug)
$toolTip.SetToolTip($chkPsDebug, 'Off by default. This is GStreamer Glass wrapper script diagnostics (not gst-launch/GST_DEBUG output): app lifecycle, settings load/save, and dialog tracing. Written to a psdebug-*.log file in the same log folder as everything else, and shown live in the Logs tab, regardless of Write process logs to disk.')

$chkMinimizeToTray = New-Object System.Windows.Forms.CheckBox
$chkMinimizeToTray.Text = 'Minimize to tray'
$chkMinimizeToTray.Location = New-Object System.Drawing.Point(600, 130)
$chkMinimizeToTray.Size = New-Object System.Drawing.Size(120, 23)
$chkMinimizeToTray.Checked = $true
$settingsGroup.Controls.Add($chkMinimizeToTray)
$toolTip.SetToolTip($chkMinimizeToTray, 'Hides the main window in the notification area when minimized. Closing the window still exits and terminates GStreamer.')

# Per-tab reset buttons. These restore GStreamer Glass app defaults only.
$btnResetTransport = New-Object System.Windows.Forms.Button
$btnResetTransport.Text = 'Reset Transport Defaults'
$btnResetTransport.Location = New-Object System.Drawing.Point(15, 548)
$btnResetTransport.Size = New-Object System.Drawing.Size(170, 30)
$settingsGroup.Controls.Add($btnResetTransport)

$btnResetWebRtcSane = New-Object System.Windows.Forms.Button
$btnResetWebRtcSane.Text = 'Reset WebRTC Sane Defaults'
$btnResetWebRtcSane.Location = New-Object System.Drawing.Point(15, 548)
$btnResetWebRtcSane.Size = New-Object System.Drawing.Size(190, 30)
$settingsGroup.Controls.Add($btnResetWebRtcSane)

$btnResetVideo = New-Object System.Windows.Forms.Button
$btnResetVideo.Text = 'Reset Video Defaults'
$btnResetVideo.Location = New-Object System.Drawing.Point(15, 548)
$btnResetVideo.Size = New-Object System.Drawing.Size(150, 30)
$settingsGroup.Controls.Add($btnResetVideo)

$btnResetAudio = New-Object System.Windows.Forms.Button
$btnResetAudio.Text = 'Reset Audio Defaults'
$btnResetAudio.Location = New-Object System.Drawing.Point(15, 548)
$btnResetAudio.Size = New-Object System.Drawing.Size(150, 30)
$settingsGroup.Controls.Add($btnResetAudio)

$btnResetRecording = New-Object System.Windows.Forms.Button
$btnResetRecording.Text = 'Reset Recording Defaults'
$btnResetRecording.Location = New-Object System.Drawing.Point(15, 548)
$btnResetRecording.Size = New-Object System.Drawing.Size(170, 30)
$settingsGroup.Controls.Add($btnResetRecording)

$btnResetNetwork = New-Object System.Windows.Forms.Button
$btnResetNetwork.Text = 'Reset Network Tab Defaults'
$btnResetNetwork.Location = New-Object System.Drawing.Point(15, 548)
$btnResetNetwork.Size = New-Object System.Drawing.Size(180, 30)
$settingsGroup.Controls.Add($btnResetNetwork)

$btnResetOptions = New-Object System.Windows.Forms.Button
$btnResetOptions.Text = 'Reset Options Defaults'
$btnResetOptions.Location = New-Object System.Drawing.Point(15, 548)
$btnResetOptions.Size = New-Object System.Drawing.Size(160, 30)
$settingsGroup.Controls.Add($btnResetOptions)

$btnExportLabConfig = New-Object System.Windows.Forms.Button
$btnExportLabConfig.Text = 'Export Lab Config'
$btnExportLabConfig.Location = New-Object System.Drawing.Point(15, 548)
$btnExportLabConfig.Size = New-Object System.Drawing.Size(160, 30)
$settingsGroup.Controls.Add($btnExportLabConfig)
$toolTip.SetToolTip($btnExportLabConfig, 'Export the complete current settings snapshot plus the exact generated gst-launch command to a portable JSON file.')

$cmbProfilePreset = New-Object System.Windows.Forms.ComboBox
$cmbProfilePreset.Location = New-Object System.Drawing.Point(15, 548)
$cmbProfilePreset.Size = New-Object System.Drawing.Size(260, 23)
$cmbProfilePreset.DropDownStyle = 'DropDownList'
$settingsGroup.Controls.Add($cmbProfilePreset)
$toolTip.SetToolTip($cmbProfilePreset, 'Bundled and custom settings presets, filtered to whatever is compatible with the currently selected protocol.')

$lblProfileDescription = New-Object System.Windows.Forms.Label
$lblProfileDescription.Text = 'No profile selected.'
$lblProfileDescription.Location = New-Object System.Drawing.Point(15, 548)
$lblProfileDescription.Size = New-Object System.Drawing.Size(560, 40)
$lblProfileDescription.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblProfileDescription)

$btnLoadProfile = New-Object System.Windows.Forms.Button
$btnLoadProfile.Text = 'Load'
$btnLoadProfile.Location = New-Object System.Drawing.Point(15, 548)
$btnLoadProfile.Size = New-Object System.Drawing.Size(140, 30)
$settingsGroup.Controls.Add($btnLoadProfile)
$toolTip.SetToolTip($btnLoadProfile, 'Apply the selected profile. This replaces ALL current settings with the profile''s saved values (confirmation required).')

$btnSaveProfile = New-Object System.Windows.Forms.Button
$btnSaveProfile.Text = 'Save'
$btnSaveProfile.Location = New-Object System.Drawing.Point(15, 548)
$btnSaveProfile.Size = New-Object System.Drawing.Size(140, 30)
$settingsGroup.Controls.Add($btnSaveProfile)
$toolTip.SetToolTip($btnSaveProfile, 'Overwrite the selected custom profile with the current settings. Disabled for built-in profiles -- use Save As instead.')

$btnSaveProfileAs = New-Object System.Windows.Forms.Button
$btnSaveProfileAs.Text = 'Save As...'
$btnSaveProfileAs.Location = New-Object System.Drawing.Point(15, 548)
$btnSaveProfileAs.Size = New-Object System.Drawing.Size(140, 30)
$settingsGroup.Controls.Add($btnSaveProfileAs)
$toolTip.SetToolTip($btnSaveProfileAs, 'Save the current settings as a new named custom profile.')

$btnDeleteProfile = New-Object System.Windows.Forms.Button
$btnDeleteProfile.Text = 'Delete'
$btnDeleteProfile.Location = New-Object System.Drawing.Point(15, 548)
$btnDeleteProfile.Size = New-Object System.Drawing.Size(140, 30)
$settingsGroup.Controls.Add($btnDeleteProfile)
$toolTip.SetToolTip($btnDeleteProfile, 'Delete the selected custom profile. Disabled for built-in profiles.')

$btnExportProfile = New-Object System.Windows.Forms.Button
$btnExportProfile.Text = 'Export...'
$btnExportProfile.Location = New-Object System.Drawing.Point(15, 548)
$btnExportProfile.Size = New-Object System.Drawing.Size(140, 30)
$settingsGroup.Controls.Add($btnExportProfile)
$toolTip.SetToolTip($btnExportProfile, 'Export the selected profile (built-in or custom) to a portable JSON file.')

$btnImportProfile = New-Object System.Windows.Forms.Button
$btnImportProfile.Text = 'Import...'
$btnImportProfile.Location = New-Object System.Drawing.Point(15, 548)
$btnImportProfile.Size = New-Object System.Drawing.Size(140, 30)
$settingsGroup.Controls.Add($btnImportProfile)
$toolTip.SetToolTip($btnImportProfile, 'Import a previously exported .gstglass.json file as a new named custom profile.')

$lblThreadingProfile = Add-Label $settingsGroup 'Threading profile' 15 548 120

$cmbThreadingProfile = New-Object System.Windows.Forms.ComboBox
$cmbThreadingProfile.Location = New-Object System.Drawing.Point(15, 548)
$cmbThreadingProfile.Size = New-Object System.Drawing.Size(165, 23)
$cmbThreadingProfile.DropDownStyle = 'DropDownList'
$null = $cmbThreadingProfile.Items.AddRange([string[]]@('Live strict','Balanced','Non-blocking brutal','Blocking diagnostic','Custom'))
$cmbThreadingProfile.SelectedItem = $script:DefaultThreadingProfile
$settingsGroup.Controls.Add($cmbThreadingProfile)
$toolTip.SetToolTip($cmbThreadingProfile, 'Runtime queue/threading profile. Live strict keeps queues tiny and leaky. Blocking diagnostic intentionally allows backpressure to prove where stalls start.')

$lblGstProcessPriority = Add-Label $settingsGroup 'GST priority' 15 548 90

$cmbGstProcessPriority = New-Object System.Windows.Forms.ComboBox
$cmbGstProcessPriority.Location = New-Object System.Drawing.Point(15, 548)
$cmbGstProcessPriority.Size = New-Object System.Drawing.Size(120, 23)
$cmbGstProcessPriority.DropDownStyle = 'DropDownList'
$null = $cmbGstProcessPriority.Items.AddRange([string[]]@('Normal','Above normal','High'))
$cmbGstProcessPriority.SelectedItem = $script:DefaultGstProcessPriority
$settingsGroup.Controls.Add($cmbGstProcessPriority)
$toolTip.SetToolTip($cmbGstProcessPriority, 'Windows process priority for gst-launch after start. High can help capture/encode threads get scheduled under game load.')

$lblThreadBudget = Add-Label $settingsGroup 'Thread budget' 15 548 100
$cmbThreadBudget = New-Object System.Windows.Forms.ComboBox
$cmbThreadBudget.DropDownStyle = 'DropDownList'
$null = $cmbThreadBudget.Items.AddRange([string[]]@('Automatic','Lean','Balanced','Isolated','Custom'))
$cmbThreadBudget.SelectedItem = $script:DefaultThreadBudget
$settingsGroup.Controls.Add($cmbThreadBudget)
$toolTip.SetToolTip($cmbThreadBudget, 'Controls optional GStreamer queue thread boundaries and supported CPU worker limits. This cannot cap driver, WASAPI, or WebRTC internal threads.')

$lblCpuWorkerLimit = Add-Label $settingsGroup 'CPU workers' 15 548 90
$numCpuWorkerLimit = New-Object System.Windows.Forms.NumericUpDown
$numCpuWorkerLimit.Minimum = 0
$numCpuWorkerLimit.Maximum = 32
$numCpuWorkerLimit.Value = $script:DefaultCpuWorkerLimit
$settingsGroup.Controls.Add($numCpuWorkerLimit)
$toolTip.SetToolTip($numCpuWorkerLimit, 'Worker cap for supported CPU elements such as compositor, videoconvert, and x264enc. 0 leaves the element on automatic. It does not cap total process threads.')

$chkBudgetCaptureQueue = New-Object System.Windows.Forms.CheckBox
$chkBudgetCaptureQueue.Text = 'Capture -> encoder thread'
$chkBudgetCaptureQueue.AutoSize = $true
$chkBudgetCaptureQueue.Checked = $true
$settingsGroup.Controls.Add($chkBudgetCaptureQueue)

$chkBudgetSenderQueue = New-Object System.Windows.Forms.CheckBox
$chkBudgetSenderQueue.Text = 'Encoder -> sender thread'
$chkBudgetSenderQueue.AutoSize = $true
$chkBudgetSenderQueue.Checked = $true
$settingsGroup.Controls.Add($chkBudgetSenderQueue)

$chkBudgetAudioInputQueue = New-Object System.Windows.Forms.CheckBox
$chkBudgetAudioInputQueue.Text = 'Audio input thread'
$chkBudgetAudioInputQueue.AutoSize = $true
$chkBudgetAudioInputQueue.Checked = $true
$settingsGroup.Controls.Add($chkBudgetAudioInputQueue)

$chkBudgetAudioFinalQueue = New-Object System.Windows.Forms.CheckBox
$chkBudgetAudioFinalQueue.Text = 'Audio sender thread'
$chkBudgetAudioFinalQueue.AutoSize = $true
$chkBudgetAudioFinalQueue.Checked = $true
$settingsGroup.Controls.Add($chkBudgetAudioFinalQueue)

$chkBudgetSceneInputQueues = New-Object System.Windows.Forms.CheckBox
$chkBudgetSceneInputQueues.Text = 'Scene input threads (required)'
$chkBudgetSceneInputQueues.AutoSize = $true
$chkBudgetSceneInputQueues.Checked = $true
$settingsGroup.Controls.Add($chkBudgetSceneInputQueues)

$lblLiveGstThreads = New-Object System.Windows.Forms.Label
$lblLiveGstThreads.Text = 'Live GST threads: stopped'
$lblLiveGstThreads.AutoSize = $true
$settingsGroup.Controls.Add($lblLiveGstThreads)
$toolTip.SetToolTip($lblLiveGstThreads, 'Observed Windows thread count for gst-launch-1.0.exe. Includes GStreamer, plugin, driver, audio, GPU, networking, and housekeeping threads.')

$lblQueueLeakMode = Add-Label $settingsGroup 'Queue leak' 15 548 90

$cmbQueueLeakMode = New-Object System.Windows.Forms.ComboBox
$cmbQueueLeakMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbQueueLeakMode.Size = New-Object System.Drawing.Size(170, 23)
$cmbQueueLeakMode.DropDownStyle = 'DropDownList'
$null = $cmbQueueLeakMode.Items.AddRange([string[]]@('Downstream - drop old','Upstream - drop new','No leak - block'))
$cmbQueueLeakMode.SelectedItem = $script:DefaultQueueLeakMode
$settingsGroup.Controls.Add($cmbQueueLeakMode)
$toolTip.SetToolTip($cmbQueueLeakMode, 'How live queues behave when full. Downstream drops old frames and is usually right for live desktop. No leak blocks upstream and can rubber-band.')

$lblCaptureQueueBuffers = Add-Label $settingsGroup 'Capture q buffers' 15 548 120

$numCaptureQueueBuffers = New-Object System.Windows.Forms.NumericUpDown
$numCaptureQueueBuffers.Location = New-Object System.Drawing.Point(15, 548)
$numCaptureQueueBuffers.Size = New-Object System.Drawing.Size(70, 23)
$numCaptureQueueBuffers.Minimum = 1
$numCaptureQueueBuffers.Maximum = 16
$numCaptureQueueBuffers.Increment = 1
$numCaptureQueueBuffers.Value = $script:DefaultCaptureQueueBuffers
$settingsGroup.Controls.Add($numCaptureQueueBuffers)
$toolTip.SetToolTip($numCaptureQueueBuffers, 'Queue depth immediately before the encoder. Lower = lower latency; higher = more cushion when compositor/GPU scheduling hiccups.')

$lblAudioQueueBuffers = Add-Label $settingsGroup 'Audio q buffers' 15 548 110

$numAudioQueueBuffers = New-Object System.Windows.Forms.NumericUpDown
$numAudioQueueBuffers.Location = New-Object System.Drawing.Point(15, 548)
$numAudioQueueBuffers.Size = New-Object System.Drawing.Size(70, 23)
$numAudioQueueBuffers.Minimum = 1
$numAudioQueueBuffers.Maximum = 32
$numAudioQueueBuffers.Increment = 1
$numAudioQueueBuffers.Value = $script:DefaultAudioQueueBuffers
$settingsGroup.Controls.Add($numAudioQueueBuffers)
$toolTip.SetToolTip($numAudioQueueBuffers, 'Audio queue buffer depth. If audio clock is dragging video, smaller/leaky audio queues help reveal it.')

$lblAudioQueueCapMs = Add-Label $settingsGroup 'Audio queue cap ms' 15 548 130

$numAudioQueueCapMs = New-Object System.Windows.Forms.NumericUpDown
$numAudioQueueCapMs.Location = New-Object System.Drawing.Point(15, 548)
$numAudioQueueCapMs.Size = New-Object System.Drawing.Size(80, 23)
$numAudioQueueCapMs.Minimum = 0
$numAudioQueueCapMs.Maximum = 500
$numAudioQueueCapMs.Increment = 10
$numAudioQueueCapMs.Value = $script:DefaultAudioQueueCapMs
$settingsGroup.Controls.Add($numAudioQueueCapMs)
$toolTip.SetToolTip($numAudioQueueCapMs, 'Optional audio queue time cap. 0 disables time cap. Nonzero caps below the safe live-audio floor are clamped at runtime to avoid GStreamer latency errors.')

$chkBufferLatenessTracer = New-Object System.Windows.Forms.CheckBox
$chkBufferLatenessTracer.Text = 'Buffer lateness tracer'
$chkBufferLatenessTracer.Location = New-Object System.Drawing.Point(15, 548)
$chkBufferLatenessTracer.Size = New-Object System.Drawing.Size(190, 24)
$chkBufferLatenessTracer.Checked = $script:DefaultBufferLatenessTracer
$settingsGroup.Controls.Add($chkBufferLatenessTracer)
$toolTip.SetToolTip($chkBufferLatenessTracer, 'Enables GST_TRACERS=buffer-lateness and GST_DEBUG=GST_TRACER:7 for gst-launch. Use only while diagnosing; logs get noisy.')

$lblGstDebugMode = Add-Label $settingsGroup 'GST debug' 15 548 90

$cmbGstDebugMode = New-Object System.Windows.Forms.ComboBox
$cmbGstDebugMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbGstDebugMode.Size = New-Object System.Drawing.Size(170, 23)
$cmbGstDebugMode.DropDownStyle = 'DropDownList'
$null = $cmbGstDebugMode.Items.AddRange([string[]]@('Off','ERROR (*:1)','WARNING (*:2)','INFO (*:3)','DEBUG (*:4)','LOG (*:5)','TRACE (*:6)','FULL/MEMDUMP (*:9)','Custom'))
$cmbGstDebugMode.SelectedItem = $script:DefaultGstDebugMode
$settingsGroup.Controls.Add($cmbGstDebugMode)
$toolTip.SetToolTip($cmbGstDebugMode, 'Sets GST_DEBUG for the gst-launch process only. DEBUG/TRACE/FULL are very noisy but useful for latency/desync diagnosis.')

$lblGstDebugSpec = Add-Label $settingsGroup 'GST_DEBUG spec' 15 548 120

$txtGstDebugSpec = New-Object System.Windows.Forms.TextBox
$txtGstDebugSpec.Location = New-Object System.Drawing.Point(15, 548)
$txtGstDebugSpec.Size = New-Object System.Drawing.Size(185, 23)
$txtGstDebugSpec.Text = $script:DefaultGstDebugSpec
$settingsGroup.Controls.Add($txtGstDebugSpec)
$toolTip.SetToolTip($txtGstDebugSpec, 'Custom GST_DEBUG value, for example *:4,webrtc*:6,rtp*:6,rtpjitterbuffer:6,wasapi*:6. Used only when mode is Custom; presets show their generated spec here.')

$chkGstDebugNoColor = New-Object System.Windows.Forms.CheckBox
$chkGstDebugNoColor.Text = 'No debug color'
$chkGstDebugNoColor.Location = New-Object System.Drawing.Point(15, 548)
$chkGstDebugNoColor.Size = New-Object System.Drawing.Size(135, 24)
$chkGstDebugNoColor.Checked = $script:DefaultGstDebugNoColor
$settingsGroup.Controls.Add($chkGstDebugNoColor)
$toolTip.SetToolTip($chkGstDebugNoColor, 'Sets GST_DEBUG_NO_COLOR=1 so redirected logs are readable in the app/log files.')

$lblJbufWatchdogMode = Add-Label $settingsGroup 'JBUF watchdog' 15 548 115

$cmbJbufWatchdogMode = New-Object System.Windows.Forms.ComboBox
$cmbJbufWatchdogMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbJbufWatchdogMode.Size = New-Object System.Drawing.Size(170, 23)
$cmbJbufWatchdogMode.DropDownStyle = 'DropDownList'
$null = $cmbJbufWatchdogMode.Items.AddRange([string[]]@('Off','Warn only','Auto-reconnect viewer'))
$cmbJbufWatchdogMode.SelectedItem = $script:DefaultJbufWatchdogMode
$settingsGroup.Controls.Add($cmbJbufWatchdogMode)
$toolTip.SetToolTip($cmbJbufWatchdogMode, 'Browser-side guard for growing WebRTC jitter buffer. Warn only paints status; Auto-reconnect viewer tears down the browser PeerConnection when JBUF keeps exceeding the threshold.')

$lblJbufMaxMs = Add-Label $settingsGroup 'JBUF max ms' 15 548 100

$numJbufMaxMs = New-Object System.Windows.Forms.NumericUpDown
$numJbufMaxMs.Location = New-Object System.Drawing.Point(15, 548)
$numJbufMaxMs.Size = New-Object System.Drawing.Size(80, 23)
$numJbufMaxMs.Minimum = 5
$numJbufMaxMs.Maximum = 500
$numJbufMaxMs.Increment = 5
$numJbufMaxMs.Value = $script:DefaultJbufMaxMs
$settingsGroup.Controls.Add($numJbufMaxMs)
$toolTip.SetToolTip($numJbufMaxMs, 'Browser-side JBUF warning/reconnect threshold. This is a watchdog threshold, not a guaranteed hard browser limit.')

$chkPlayerStatsOverlay = New-Object System.Windows.Forms.CheckBox
$chkPlayerStatsOverlay.Text = 'Stats overlay'
$chkPlayerStatsOverlay.Location = New-Object System.Drawing.Point(15, 548)
$chkPlayerStatsOverlay.Size = New-Object System.Drawing.Size(130, 24)
$chkPlayerStatsOverlay.Checked = $script:DefaultPlayerStatsOverlay
$settingsGroup.Controls.Add($chkPlayerStatsOverlay)
$toolTip.SetToolTip($chkPlayerStatsOverlay, 'Show the browser player stats overlay. Written to gstglass-config.js as statsOverlay.')

$chkPlayerJbufDebug = New-Object System.Windows.Forms.CheckBox
$chkPlayerJbufDebug.Text = 'JBUF debug logging'
$chkPlayerJbufDebug.Location = New-Object System.Drawing.Point(15, 548)
$chkPlayerJbufDebug.Size = New-Object System.Drawing.Size(155, 24)
$chkPlayerJbufDebug.Checked = $script:DefaultPlayerJbufDebug
$settingsGroup.Controls.Add($chkPlayerJbufDebug)
$toolTip.SetToolTip($chkPlayerJbufDebug, 'Enable browser console logging for player.js JBUF target/config resolution.')

$numLiveEdgeAverageSec = New-Object System.Windows.Forms.NumericUpDown
$numLiveEdgeAverageSec.Location = New-Object System.Drawing.Point(15, 548)
$numLiveEdgeAverageSec.Size = New-Object System.Drawing.Size(70, 23)
$numLiveEdgeAverageSec.Minimum = 1
$numLiveEdgeAverageSec.Maximum = 30
$numLiveEdgeAverageSec.Increment = 1
$numLiveEdgeAverageSec.Value = $script:DefaultLiveEdgeAverageSec
$settingsGroup.Controls.Add($numLiveEdgeAverageSec)
$toolTip.SetToolTip($numLiveEdgeAverageSec, 'Rolling average window for Live Edge excess latency. Shorter reacts faster; longer is steadier. Range 1-30 seconds.')

$numLiveEdgeGreenMs = New-Object System.Windows.Forms.NumericUpDown
$numLiveEdgeGreenMs.Location = New-Object System.Drawing.Point(15, 548)
$numLiveEdgeGreenMs.Size = New-Object System.Drawing.Size(80, 23)
$numLiveEdgeGreenMs.Minimum = 1
$numLiveEdgeGreenMs.Maximum = 4999
$numLiveEdgeGreenMs.Increment = 1
$numLiveEdgeGreenMs.Value = $script:DefaultLiveEdgeGreenMs
$settingsGroup.Controls.Add($numLiveEdgeGreenMs)
$toolTip.SetToolTip($numLiveEdgeGreenMs, 'Maximum rolling excess-latency average shown as green / Live.')

$numLiveEdgeYellowMs = New-Object System.Windows.Forms.NumericUpDown
$numLiveEdgeYellowMs.Location = New-Object System.Drawing.Point(15, 548)
$numLiveEdgeYellowMs.Size = New-Object System.Drawing.Size(80, 23)
$numLiveEdgeYellowMs.Minimum = 2
$numLiveEdgeYellowMs.Maximum = 5000
$numLiveEdgeYellowMs.Increment = 1
$numLiveEdgeYellowMs.Value = $script:DefaultLiveEdgeYellowMs
$settingsGroup.Controls.Add($numLiveEdgeYellowMs)
$toolTip.SetToolTip($numLiveEdgeYellowMs, 'Maximum rolling excess-latency average shown as yellow / Delayed. Values above this are red.')

$chkPlayerUrlOverrides = New-Object System.Windows.Forms.CheckBox
$chkPlayerUrlOverrides.Text = 'Open/copy with URL overrides'
$chkPlayerUrlOverrides.Location = New-Object System.Drawing.Point(15, 548)
$chkPlayerUrlOverrides.Size = New-Object System.Drawing.Size(220, 24)
$chkPlayerUrlOverrides.Checked = $script:DefaultPlayerUrlOverrides
$settingsGroup.Controls.Add($chkPlayerUrlOverrides)
$toolTip.SetToolTip($chkPlayerUrlOverrides, 'Debug escape hatch. Off = clean /live/ URL uses gstglass-config.js. On = append current Player tab values as query overrides.')

$txtPlayerVideoSignalingProxyPath = New-Object System.Windows.Forms.TextBox
$txtPlayerVideoSignalingProxyPath.Location = New-Object System.Drawing.Point(15, 548)
$txtPlayerVideoSignalingProxyPath.Size = New-Object System.Drawing.Size(260, 23)
$txtPlayerVideoSignalingProxyPath.Text = $script:DefaultPlayerVideoSignalingProxyPath
$settingsGroup.Controls.Add($txtPlayerVideoSignalingProxyPath)
$toolTip.SetToolTip($txtPlayerVideoSignalingProxyPath, 'Preferred path-based WebSocket signaling endpoint for video. Used first in AUTO, LAN, and PROXY; mapped/direct ports remain fallbacks. Example: /live/GstSignal/video')

$txtPlayerAudioSignalingProxyPath = New-Object System.Windows.Forms.TextBox
$txtPlayerAudioSignalingProxyPath.Location = New-Object System.Drawing.Point(15, 548)
$txtPlayerAudioSignalingProxyPath.Size = New-Object System.Drawing.Size(260, 23)
$txtPlayerAudioSignalingProxyPath.Text = $script:DefaultPlayerAudioSignalingProxyPath
$settingsGroup.Controls.Add($txtPlayerAudioSignalingProxyPath)
$toolTip.SetToolTip($txtPlayerAudioSignalingProxyPath, 'Preferred path-based WebSocket signaling endpoint for split audio/voice. The configured path is used exactly and is not rewritten. Example: /live/GstSignal/voice')

$chkSendEosOnStop = New-Object System.Windows.Forms.CheckBox
$chkSendEosOnStop.Text = 'Send EOS on stop'
$chkSendEosOnStop.Location = New-Object System.Drawing.Point(15, 548)
$chkSendEosOnStop.Size = New-Object System.Drawing.Size(220, 24)
$chkSendEosOnStop.Checked = $script:DefaultSendEosOnStop
$settingsGroup.Controls.Add($chkSendEosOnStop)
$toolTip.SetToolTip($chkSendEosOnStop, 'Stop only: mark the stream intentionally stopped for viewers before tearing down the pipeline, so the web player shows Available and waits for Play instead of auto-reconnecting. Restart and Restart pipeline are unaffected by this setting.')

$chkPlayerSeparateHtmlMediaElements = New-Object System.Windows.Forms.CheckBox
$chkPlayerSeparateHtmlMediaElements.Text = 'Separate video and audio HTML media elements'
$chkPlayerSeparateHtmlMediaElements.Location = New-Object System.Drawing.Point(15, 548)
$chkPlayerSeparateHtmlMediaElements.Size = New-Object System.Drawing.Size(340, 24)
$chkPlayerSeparateHtmlMediaElements.Checked = $script:DefaultPlayerSeparateHtmlMediaElements
$settingsGroup.Controls.Add($chkPlayerSeparateHtmlMediaElements)
$toolTip.SetToolTip($chkPlayerSeparateHtmlMediaElements, 'Player rendering only. On attaches the video track to the video element and the audio track to a separate audio element. Off recombines both tracks into one MediaStream on the video element. Independent of A/V MediaStream grouping. Physical split WebRTC producers necessarily use separate elements.')

$cmbDirectWebRtcAvPipelineMode = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcAvPipelineMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcAvPipelineMode.Size = New-Object System.Drawing.Size(310, 23)
$cmbDirectWebRtcAvPipelineMode.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcAvPipelineMode.Items.AddRange([string[]]@('Single pipeline','Split A/V pipelines - separate gst-launch'))
$cmbDirectWebRtcAvPipelineMode.SelectedItem = $script:DefaultDirectWebRtcAvPipelineMode
$settingsGroup.Controls.Add($cmbDirectWebRtcAvPipelineMode)
$toolTip.SetToolTip($cmbDirectWebRtcAvPipelineMode, 'Direct GST WebRTC topology. Single pipeline keeps audio and video in one gst-launch pipeline. Split mode launches a second audio-only gst-launch/webrtcsink. Transport-tab controls choose separate signalling ports or one shared signalling server.')

$cmbSplitPlayerSyncMode = New-Object System.Windows.Forms.ComboBox
$cmbSplitPlayerSyncMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbSplitPlayerSyncMode.Size = New-Object System.Drawing.Size(220, 23)
$cmbSplitPlayerSyncMode.DropDownStyle = 'DropDownList'
$null = $cmbSplitPlayerSyncMode.Items.AddRange([string[]]@('Off / free-run','Audio watchdog only','Soft sync experimental'))
$cmbSplitPlayerSyncMode.SelectedItem = $script:DefaultSplitPlayerSyncMode
$settingsGroup.Controls.Add($cmbSplitPlayerSyncMode)
$toolTip.SetToolTip($cmbSplitPlayerSyncMode, 'Split A/V browser/player behavior. Default Off leaves the proven split path free-running. Audio watchdog and soft sync are opt-in experiments that only recover/reconnect the split audio side; they do not delay video.')

$numSplitAudioStallSeconds = New-Object System.Windows.Forms.NumericUpDown
$numSplitAudioStallSeconds.Location = New-Object System.Drawing.Point(15, 548)
$numSplitAudioStallSeconds.Size = New-Object System.Drawing.Size(70, 23)
$numSplitAudioStallSeconds.Minimum = 1
$numSplitAudioStallSeconds.Maximum = 30
$numSplitAudioStallSeconds.Increment = 1
$numSplitAudioStallSeconds.Value = $script:DefaultSplitAudioStallSeconds
$settingsGroup.Controls.Add($numSplitAudioStallSeconds)
$toolTip.SetToolTip($numSplitAudioStallSeconds, 'Opt-in split audio watchdog timeout. If enabled and audio stats/element look stalled this many seconds, the player recovers only the split audio path after the startup warmup window.')

$numSplitAudioWarmupSeconds = New-Object System.Windows.Forms.NumericUpDown
$numSplitAudioWarmupSeconds.Location = New-Object System.Drawing.Point(15, 548)
$numSplitAudioWarmupSeconds.Size = New-Object System.Drawing.Size(70, 23)
$numSplitAudioWarmupSeconds.Minimum = 0
$numSplitAudioWarmupSeconds.Maximum = 600
$numSplitAudioWarmupSeconds.Increment = 1
$numSplitAudioWarmupSeconds.Value = $script:DefaultSplitAudioWarmupSeconds
$settingsGroup.Controls.Add($numSplitAudioWarmupSeconds)
$toolTip.SetToolTip($numSplitAudioWarmupSeconds, 'Opt-in startup/equalization grace period for both browser JBUF watchdog and split audio watchdog/soft-sync recovery. Recovery/reconnect is blocked until this many seconds after primary or split audio connects/receives media. Range 0-600 seconds.')

$numSplitAvOffsetWarnMs = New-Object System.Windows.Forms.NumericUpDown
$numSplitAvOffsetWarnMs.Location = New-Object System.Drawing.Point(15, 548)
$numSplitAvOffsetWarnMs.Size = New-Object System.Drawing.Size(80, 23)
$numSplitAvOffsetWarnMs.Minimum = 20
$numSplitAvOffsetWarnMs.Maximum = 1000
$numSplitAvOffsetWarnMs.Increment = 10
$numSplitAvOffsetWarnMs.Value = $script:DefaultSplitAvOffsetWarnMs
$settingsGroup.Controls.Add($numSplitAvOffsetWarnMs)
$toolTip.SetToolTip($numSplitAvOffsetWarnMs, 'Opt-in split A/V soft-sync drift threshold. This compares current estimated A/V offset against the learned/configured baseline, not against zero. Video is never delayed by this feature.')

$numSplitAvOffsetBaselineMs = New-Object System.Windows.Forms.NumericUpDown
$numSplitAvOffsetBaselineMs.Location = New-Object System.Drawing.Point(15, 548)
$numSplitAvOffsetBaselineMs.Size = New-Object System.Drawing.Size(80, 23)
$numSplitAvOffsetBaselineMs.Minimum = 0
$numSplitAvOffsetBaselineMs.Maximum = 1000
$numSplitAvOffsetBaselineMs.Increment = 1
$numSplitAvOffsetBaselineMs.Value = $script:DefaultSplitAvOffsetBaselineMs
$settingsGroup.Controls.Add($numSplitAvOffsetBaselineMs)
$toolTip.SetToolTip($numSplitAvOffsetBaselineMs, 'Opt-in split A/V healthy offset baseline in ms. 0 = auto-learn after watchdog warmup. Example: audio 59ms - video 16ms = baseline 43ms, and only drift above that is considered bad.')

$btnResetAll = New-Object System.Windows.Forms.Button
$btnResetAll.Text = 'Reset All App Defaults'
$btnResetAll.Location = New-Object System.Drawing.Point(15, 548)
$btnResetAll.Size = New-Object System.Drawing.Size(170, 30)
$settingsGroup.Controls.Add($btnResetAll)


$null = Add-Label $settingsGroup 'Width' 15 166 45
$numWidth = New-Object System.Windows.Forms.NumericUpDown
$numWidth.Location = New-Object System.Drawing.Point(60, 166)
$numWidth.Size = New-Object System.Drawing.Size(80, 23)
$numWidth.Minimum = 320
$numWidth.Maximum = 7680
$numWidth.Increment = 16
$numWidth.Value = 1920
$settingsGroup.Controls.Add($numWidth)

$null = Add-Label $settingsGroup 'Height' 150 166 48
$numHeight = New-Object System.Windows.Forms.NumericUpDown
$numHeight.Location = New-Object System.Drawing.Point(198, 166)
$numHeight.Size = New-Object System.Drawing.Size(80, 23)
$numHeight.Minimum = 240
$numHeight.Maximum = 4320
$numHeight.Increment = 16
$numHeight.Value = 1080
$settingsGroup.Controls.Add($numHeight)

$null = Add-Label $settingsGroup 'FPS' 290 166 35
$numFps = New-Object System.Windows.Forms.NumericUpDown
$numFps.Location = New-Object System.Drawing.Point(325, 166)
$numFps.Size = New-Object System.Drawing.Size(60, 23)
$numFps.Minimum = 1
$numFps.Maximum = 240
$numFps.Value = 60
$settingsGroup.Controls.Add($numFps)

$null = Add-Label $settingsGroup 'Video kbps' 400 166 75
$numVideoBitrate = New-Object System.Windows.Forms.NumericUpDown
$numVideoBitrate.Location = New-Object System.Drawing.Point(475, 166)
$numVideoBitrate.Size = New-Object System.Drawing.Size(90, 23)
$numVideoBitrate.Minimum = 250
$numVideoBitrate.Maximum = 100000
$numVideoBitrate.Increment = 500
$numVideoBitrate.Value = 12000
$settingsGroup.Controls.Add($numVideoBitrate)
$toolTip.SetToolTip($numVideoBitrate, 'The actual encoder bitrate= value, in kbps. Parsed unclamped into the pipeline on every run, for every protocol -- nothing else in the app adjusts, floors, or overrides this. If you override it for testing, that override is exactly what runs.')

$null = Add-Label $settingsGroup 'GOP sec' 580 166 60
$numGopSeconds = New-Object System.Windows.Forms.NumericUpDown
$numGopSeconds.Location = New-Object System.Drawing.Point(640, 166)
$numGopSeconds.Size = New-Object System.Drawing.Size(60, 23)
$numGopSeconds.Minimum = 1
$numGopSeconds.Maximum = 10
$numGopSeconds.Value = 1
$settingsGroup.Controls.Add($numGopSeconds)

$chkUnifiedBridgeKeyframeGuard = New-Object System.Windows.Forms.CheckBox
$chkUnifiedBridgeKeyframeGuard.Text = 'Unified bridge periodic keyframes'
$chkUnifiedBridgeKeyframeGuard.Location = New-Object System.Drawing.Point(15, 548)
$chkUnifiedBridgeKeyframeGuard.Size = New-Object System.Drawing.Size(250, 24)
$chkUnifiedBridgeKeyframeGuard.Checked = $script:DefaultUnifiedBridgeKeyframeGuard
$settingsGroup.Controls.Add($chkUnifiedBridgeKeyframeGuard)
$toolTip.SetToolTip($chkUnifiedBridgeKeyframeGuard, 'Unified publisher only. Overrides GOP seconds with a short periodic IDR interval because browser PLI/FIR keyframe requests cannot cross the localhost RTP/process boundary. Off emits no override and uses GOP sec.')

$numUnifiedBridgeKeyframeIntervalMs = New-Object System.Windows.Forms.NumericUpDown
$numUnifiedBridgeKeyframeIntervalMs.Location = New-Object System.Drawing.Point(15, 548)
$numUnifiedBridgeKeyframeIntervalMs.Size = New-Object System.Drawing.Size(85, 23)
$numUnifiedBridgeKeyframeIntervalMs.Minimum = 100
$numUnifiedBridgeKeyframeIntervalMs.Maximum = 10000
$numUnifiedBridgeKeyframeIntervalMs.Increment = 100
$numUnifiedBridgeKeyframeIntervalMs.Value = $script:DefaultUnifiedBridgeKeyframeIntervalMs
$settingsGroup.Controls.Add($numUnifiedBridgeKeyframeIntervalMs)
$toolTip.SetToolTip($numUnifiedBridgeKeyframeIntervalMs, 'Periodic IDR/keyframe interval in milliseconds for the unified publisher video bridge. The value is converted to encoder GOP frames using the current FPS. Smaller values recover joins/reconnects faster but increase bitrate and encoder work.')


$null = Add-Label $settingsGroup 'Rate control' 15 520 90
$cmbRateControl = New-Object System.Windows.Forms.ComboBox
$cmbRateControl.Location = New-Object System.Drawing.Point(15, 548)
$cmbRateControl.Size = New-Object System.Drawing.Size(95, 23)
$cmbRateControl.DropDownStyle = 'DropDownList'
$null = $cmbRateControl.Items.AddRange([string[]]$script:RateControlModes)
$cmbRateControl.SelectedItem = 'cbr'
$settingsGroup.Controls.Add($cmbRateControl)
$toolTip.SetToolTip($cmbRateControl, 'Stream encoder rate control. CBR is safest for live transport; VBR/CQP are mostly for quality testing or recording-style workflows.')

$null = Add-Label $settingsGroup 'Max kbps' 15 520 70
$numMaxVideoBitrate = New-Object System.Windows.Forms.NumericUpDown
$numMaxVideoBitrate.Location = New-Object System.Drawing.Point(15, 548)
$numMaxVideoBitrate.Size = New-Object System.Drawing.Size(100, 23)
$numMaxVideoBitrate.Minimum = 0
$numMaxVideoBitrate.Maximum = 300000
$numMaxVideoBitrate.Increment = 500
$numMaxVideoBitrate.Value = 0
$settingsGroup.Controls.Add($numMaxVideoBitrate)
$toolTip.SetToolTip($numMaxVideoBitrate, 'Dual role: (1) VBR max for the encoder itself where supported -- 0 uses the encoder default, CBR usually ignores this; (2) for WHIP/GST WebRTC, also feeds webrtcsink max-bitrate (WebRTC/Signaling layer), independently of Encoder bitrate kbps. Nothing reconciles the two automatically -- check Encoder bitrate kbps against this when tuning.')

$null = Add-Label $settingsGroup 'CQ/QP' 15 520 60
$numConstantQp = New-Object System.Windows.Forms.NumericUpDown
$numConstantQp.Location = New-Object System.Drawing.Point(15, 548)
$numConstantQp.Size = New-Object System.Drawing.Size(70, 23)
$numConstantQp.Minimum = 0
$numConstantQp.Maximum = 51
$numConstantQp.Value = 20
$settingsGroup.Controls.Add($numConstantQp)
$toolTip.SetToolTip($numConstantQp, 'Constant QP for constqp/CQP, or constant-quality target for NVENC VBR. Lower means higher quality and bigger files/bitrate spikes.')

$null = Add-Label $settingsGroup 'Tune' 15 520 60
$cmbEncoderTune = New-Object System.Windows.Forms.ComboBox
$cmbEncoderTune.Location = New-Object System.Drawing.Point(15, 548)
$cmbEncoderTune.Size = New-Object System.Drawing.Size(165, 23)
$cmbEncoderTune.DropDownStyle = 'DropDownList'
$null = $cmbEncoderTune.Items.AddRange([string[]]$script:NvencTuneModes)
$cmbEncoderTune.SelectedItem = 'ultra-low-latency'
$settingsGroup.Controls.Add($cmbEncoderTune)
$toolTip.SetToolTip($cmbEncoderTune, 'NVENC tune. Other encoder families keep their closest low-latency/quality mapping or use Custom encoder options.')

$null = Add-Label $settingsGroup 'Multipass' 15 520 90
$cmbMultipass = New-Object System.Windows.Forms.ComboBox
$cmbMultipass.Location = New-Object System.Drawing.Point(15, 548)
$cmbMultipass.Size = New-Object System.Drawing.Size(150, 23)
$cmbMultipass.DropDownStyle = 'DropDownList'
$null = $cmbMultipass.Items.AddRange([string[]]$script:NvencMultipassModes)
$cmbMultipass.SelectedItem = 'disabled'
$settingsGroup.Controls.Add($cmbMultipass)
$toolTip.SetToolTip($cmbMultipass, 'NVENC multipass mode. Disabled is best for live ultra-low-latency; two-pass modes can improve quality but add work/latency.')

$cmbVideoPipelineClockMode = New-Object System.Windows.Forms.ComboBox
$cmbVideoPipelineClockMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbVideoPipelineClockMode.Size = New-Object System.Drawing.Size(225, 23)
$cmbVideoPipelineClockMode.DropDownStyle = 'DropDownList'
$null = $cmbVideoPipelineClockMode.Items.AddRange([string[]]@(
    'Automatic / element elected',
    'System monotonic',
    'System realtime'
))
$cmbVideoPipelineClockMode.SelectedItem = $script:DefaultVideoPipelineClockMode
$settingsGroup.Controls.Add($cmbVideoPipelineClockMode)
$toolTip.SetToolTip($cmbVideoPipelineClockMode, 'Shared pipeline master clock. Automatic preserves GStreamer clock election. System monotonic/realtime wrap the complete gst-launch graph in clockselect, so a single A/V pipeline cannot switch to the WASAPI device clock.')

$cmbVideoTimestampMode = New-Object System.Windows.Forms.ComboBox
$cmbVideoTimestampMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbVideoTimestampMode.Size = New-Object System.Drawing.Size(210, 23)
$cmbVideoTimestampMode.DropDownStyle = 'DropDownList'
$null = $cmbVideoTimestampMode.Items.AddRange([string[]]@(
    'Plugin default',
    'Pipeline running-time',
    'Source timestamps'
))
$cmbVideoTimestampMode.SelectedItem = $script:DefaultVideoTimestampMode
$settingsGroup.Controls.Add($cmbVideoTimestampMode)
$toolTip.SetToolTip($cmbVideoTimestampMode, 'Video source timestamp policy. Pipeline running-time adds do-timestamp=true to screen/webcam sources. Source timestamps adds do-timestamp=false. Plugin default leaves the capture source unchanged.')

$cmbVideoSyncMode = New-Object System.Windows.Forms.ComboBox
$cmbVideoSyncMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbVideoSyncMode.Size = New-Object System.Drawing.Size(120, 23)
$cmbVideoSyncMode.DropDownStyle = 'DropDownList'
$null = $cmbVideoSyncMode.Items.AddRange([string[]]@('Default','sync=true','sync=false'))
$cmbVideoSyncMode.SelectedItem = $script:DefaultVideoSyncMode
$settingsGroup.Controls.Add($cmbVideoSyncMode)
$toolTip.SetToolTip($cmbVideoSyncMode, 'Video branch sync lab. Default leaves transport branches unchanged and preserves existing local preview behavior. sync=true/sync=false inserts a clocksync element before compatible send/mux sinks, and applies the value to the local preview sink.')

$null = Add-Label $settingsGroup 'VBV kbits' 15 520 80
$numVbvBuffer = New-Object System.Windows.Forms.NumericUpDown
$numVbvBuffer.Location = New-Object System.Drawing.Point(15, 548)
$numVbvBuffer.Size = New-Object System.Drawing.Size(95, 23)
$numVbvBuffer.Minimum = 0
$numVbvBuffer.Maximum = 1000000
$numVbvBuffer.Increment = 500
$numVbvBuffer.Value = 0
$settingsGroup.Controls.Add($numVbvBuffer)
$toolTip.SetToolTip($numVbvBuffer, 'NVENC VBV/HRD buffer size in kbits. 0 uses the encoder default. Small buffers can reduce latency but may hurt quality.')

$chkTemporalAq = New-Object System.Windows.Forms.CheckBox
$chkTemporalAq.Text = 'Temporal AQ'
$chkTemporalAq.Location = New-Object System.Drawing.Point(15, 548)
$chkTemporalAq.Size = New-Object System.Drawing.Size(105, 23)
$chkTemporalAq.Checked = $false
$settingsGroup.Controls.Add($chkTemporalAq)
$toolTip.SetToolTip($chkTemporalAq, 'NVENC temporal adaptive quantization. Can improve motion quality; may increase encoder work and is not always ideal for latency testing.')

$null = Add-Label $settingsGroup 'Custom encoder options' 15 520 160
$txtCustomEncoderOptions = New-Object System.Windows.Forms.TextBox
$txtCustomEncoderOptions.Location = New-Object System.Drawing.Point(15, 548)
$txtCustomEncoderOptions.Size = New-Object System.Drawing.Size(520, 23)
$txtCustomEncoderOptions.Text = ''
$settingsGroup.Controls.Add($txtCustomEncoderOptions)
$toolTip.SetToolTip($txtCustomEncoderOptions, 'Raw options appended directly after the selected stream encoder element, e.g. weighted-pred=true strict-gop=true. Use for untested AMD/Intel/MF/software knobs.')

$null = Add-Label $settingsGroup 'Encoder' 15 202 60
$cmbEncoder = New-Object System.Windows.Forms.ComboBox
$cmbEncoder.Location = New-Object System.Drawing.Point(75, 202)
$cmbEncoder.Size = New-Object System.Drawing.Size(330, 23)
$cmbEncoder.DropDownStyle = 'DropDownList'
$null = $cmbEncoder.Items.AddRange([string[]]($script:EncoderCatalog.Keys))
$cmbEncoder.SelectedItem = $script:DefaultEncoderName
$settingsGroup.Controls.Add($cmbEncoder)
$toolTip.SetToolTip(
    $cmbEncoder,
    'Select a hardware or software encoder. Use Check to verify that the selected GStreamer runtime contains the required element and parser.'
)

$lblEncoderStatus = New-Object System.Windows.Forms.Label
$lblEncoderStatus.Text = 'H.264 * Hardware * D3D11'
$lblEncoderStatus.Location = New-Object System.Drawing.Point(415, 202)
$lblEncoderStatus.Size = New-Object System.Drawing.Size(303, 23)
$lblEncoderStatus.TextAlign = 'MiddleLeft'
$lblEncoderStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblEncoderStatus)

$null = Add-Label $settingsGroup 'NVENC preset' 15 238 90
$cmbPreset = New-Object System.Windows.Forms.ComboBox
$cmbPreset.Location = New-Object System.Drawing.Point(105, 238)
$cmbPreset.Size = New-Object System.Drawing.Size(80, 23)
$cmbPreset.DropDownStyle = 'DropDownList'
$null = $cmbPreset.Items.AddRange(@('p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'))
$cmbPreset.SelectedItem = 'p1'
$settingsGroup.Controls.Add($cmbPreset)

$null = Add-Label $settingsGroup 'H.264 profile' 200 238 90
$cmbProfile = New-Object System.Windows.Forms.ComboBox
$cmbProfile.Location = New-Object System.Drawing.Point(290, 238)
$cmbProfile.Size = New-Object System.Drawing.Size(145, 23)
$cmbProfile.DropDownStyle = 'DropDownList'
$null = $cmbProfile.Items.AddRange(@('constrained-baseline', 'baseline', 'main', 'high'))
$cmbProfile.SelectedItem = 'constrained-baseline'
$settingsGroup.Controls.Add($cmbProfile)

$null = Add-Label $settingsGroup 'SRT latency ms' 450 238 95
$numSrtLatency = New-Object System.Windows.Forms.NumericUpDown
$numSrtLatency.Location = New-Object System.Drawing.Point(545, 238)
$numSrtLatency.Size = New-Object System.Drawing.Size(70, 23)
$numSrtLatency.Minimum = 0
$numSrtLatency.Maximum = 10000
$numSrtLatency.Increment = 10
$numSrtLatency.Value = 50
$numSrtLatency.Enabled = $false
$settingsGroup.Controls.Add($numSrtLatency)

$null = Add-Label $settingsGroup 'RTSP' 625 238 40
$cmbRtspTransport = New-Object System.Windows.Forms.ComboBox
$cmbRtspTransport.Location = New-Object System.Drawing.Point(665, 238)
$cmbRtspTransport.Size = New-Object System.Drawing.Size(55, 23)
$cmbRtspTransport.DropDownStyle = 'DropDownList'
$null = $cmbRtspTransport.Items.AddRange(@('TCP', 'UDP'))
$cmbRtspTransport.SelectedItem = 'TCP'
$cmbRtspTransport.Enabled = $false
$settingsGroup.Controls.Add($cmbRtspTransport)

$null = Add-Label $settingsGroup 'B-frames' 15 278 60
$numBFrames = New-Object System.Windows.Forms.NumericUpDown
$numBFrames.Location = New-Object System.Drawing.Point(75, 278)
$numBFrames.Size = New-Object System.Drawing.Size(55, 23)
$numBFrames.Minimum = 0
$numBFrames.Maximum = 4
$numBFrames.Value = 0
$settingsGroup.Controls.Add($numBFrames)
$toolTip.SetToolTip($numBFrames, 'Leave at 0 for lowest latency and WebRTC-compatible H.264.')

$chkLookAhead = New-Object System.Windows.Forms.CheckBox
$chkLookAhead.Text = 'Look-ahead'
$chkLookAhead.Location = New-Object System.Drawing.Point(150, 278)
$chkLookAhead.Size = New-Object System.Drawing.Size(90, 23)
$chkLookAhead.Checked = $false
$settingsGroup.Controls.Add($chkLookAhead)
$toolTip.SetToolTip($chkLookAhead, 'Enables encoder look-ahead where supported; this adds frame latency.')

$null = Add-Label $settingsGroup 'Frames' 240 278 48
$numLookAheadFrames = New-Object System.Windows.Forms.NumericUpDown
$numLookAheadFrames.Location = New-Object System.Drawing.Point(288, 278)
$numLookAheadFrames.Size = New-Object System.Drawing.Size(55, 23)
$numLookAheadFrames.Minimum = 1
$numLookAheadFrames.Maximum = 64
$numLookAheadFrames.Value = 20
$numLookAheadFrames.Enabled = $false
$settingsGroup.Controls.Add($numLookAheadFrames)

$chkAdaptiveQuantization = New-Object System.Windows.Forms.CheckBox
$chkAdaptiveQuantization.Text = 'Spatial AQ'
$chkAdaptiveQuantization.Location = New-Object System.Drawing.Point(365, 278)
$chkAdaptiveQuantization.Size = New-Object System.Drawing.Size(150, 23)
$chkAdaptiveQuantization.Checked = $false
$settingsGroup.Controls.Add($chkAdaptiveQuantization)

$null = Add-Label $settingsGroup 'AQ strength' 525 278 75
$numAqStrength = New-Object System.Windows.Forms.NumericUpDown
$numAqStrength.Location = New-Object System.Drawing.Point(600, 278)
$numAqStrength.Size = New-Object System.Drawing.Size(55, 23)
$numAqStrength.Minimum = 1
$numAqStrength.Maximum = 15
$numAqStrength.Value = 8
$numAqStrength.Enabled = $false
$settingsGroup.Controls.Add($numAqStrength)

$chkDesktopAudio = New-Object System.Windows.Forms.CheckBox
$chkDesktopAudio.Text = 'Desktop audio'
$chkDesktopAudio.Location = New-Object System.Drawing.Point(15, 316)
$chkDesktopAudio.Size = New-Object System.Drawing.Size(115, 23)
$chkDesktopAudio.Checked = $true
$settingsGroup.Controls.Add($chkDesktopAudio)

$chkAudioMixerMode = New-Object System.Windows.Forms.CheckBox
$chkAudioMixerMode.Text = 'Route through audio mix'
$chkAudioMixerMode.Location = New-Object System.Drawing.Point(565, 316)
$chkAudioMixerMode.Size = New-Object System.Drawing.Size(245, 23)
$chkAudioMixerMode.Checked = $script:DefaultAudioMixerMode
$settingsGroup.Controls.Add($chkAudioMixerMode)
$toolTip.SetToolTip($chkAudioMixerMode, 'Recommended timing-normalization path. When enabled, the active single audio source is routed through audio mix before encoding. Uncheck to restore the legacy direct WASAPI-to-encoder path. Desktop + microphone always requires audio mix to combine both sources.')

$null = Add-Label $settingsGroup 'Volume %' 130 316 65
$numDesktopVolume = New-Object System.Windows.Forms.NumericUpDown
$numDesktopVolume.Location = New-Object System.Drawing.Point(195, 316)
$numDesktopVolume.Size = New-Object System.Drawing.Size(65, 23)
$numDesktopVolume.Minimum = 0
$numDesktopVolume.Maximum = 200
$numDesktopVolume.Value = 100
$settingsGroup.Controls.Add($numDesktopVolume)

$chkMic = New-Object System.Windows.Forms.CheckBox
$chkMic.Text = 'Default microphone'
$chkMic.Location = New-Object System.Drawing.Point(280, 316)
$chkMic.Size = New-Object System.Drawing.Size(140, 23)
$chkMic.Checked = $false
$settingsGroup.Controls.Add($chkMic)

$null = Add-Label $settingsGroup 'Volume %' 420 316 65
$numMicVolume = New-Object System.Windows.Forms.NumericUpDown
$numMicVolume.Location = New-Object System.Drawing.Point(485, 316)
$numMicVolume.Size = New-Object System.Drawing.Size(65, 23)
$numMicVolume.Minimum = 0
$numMicVolume.Maximum = 200
$numMicVolume.Value = 100
$settingsGroup.Controls.Add($numMicVolume)

$null = Add-Label $settingsGroup 'Desktop device' 15 354 95
$cmbDesktopAudioDevice = New-Object System.Windows.Forms.ComboBox
$cmbDesktopAudioDevice.Location = New-Object System.Drawing.Point(115, 354)
$cmbDesktopAudioDevice.Size = New-Object System.Drawing.Size(420, 23)
$cmbDesktopAudioDevice.DropDownStyle = 'DropDownList'
$null = $cmbDesktopAudioDevice.Items.Add($script:DefaultAudioOutputDeviceLabel)
$cmbDesktopAudioDevice.SelectedIndex = 0
$settingsGroup.Controls.Add($cmbDesktopAudioDevice)
$toolTip.SetToolTip($cmbDesktopAudioDevice, 'WASAPI output endpoint used when Desktop audio is enabled. Loopback captures what that selected output device plays.')

$btnRefreshAudioDevices = New-Object System.Windows.Forms.Button
$btnRefreshAudioDevices.Text = 'Refresh audio devices'
$btnRefreshAudioDevices.Location = New-Object System.Drawing.Point(550, 354)
$btnRefreshAudioDevices.Size = New-Object System.Drawing.Size(150, 24)
$settingsGroup.Controls.Add($btnRefreshAudioDevices)
$toolTip.SetToolTip($btnRefreshAudioDevices, 'Runs gst-device-monitor and populates WASAPI input/output endpoints.')

$null = Add-Label $settingsGroup 'Mic device' 15 392 95
$cmbMicAudioDevice = New-Object System.Windows.Forms.ComboBox
$cmbMicAudioDevice.Location = New-Object System.Drawing.Point(115, 392)
$cmbMicAudioDevice.Size = New-Object System.Drawing.Size(420, 23)
$cmbMicAudioDevice.DropDownStyle = 'DropDownList'
$null = $cmbMicAudioDevice.Items.Add($script:DefaultAudioInputDeviceLabel)
$cmbMicAudioDevice.SelectedIndex = 0
$settingsGroup.Controls.Add($cmbMicAudioDevice)
$toolTip.SetToolTip($cmbMicAudioDevice, 'WASAPI capture endpoint used when Default microphone/Mic audio is enabled.')

$lblAudioDeviceStatus = New-Object System.Windows.Forms.Label
$lblAudioDeviceStatus.Text = 'Audio devices: defaults until refreshed'
$lblAudioDeviceStatus.Location = New-Object System.Drawing.Point(550, 392)
$lblAudioDeviceStatus.Size = New-Object System.Drawing.Size(260, 23)
$lblAudioDeviceStatus.TextAlign = 'MiddleLeft'
$lblAudioDeviceStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblAudioDeviceStatus)

$null = Add-Label $settingsGroup 'A/V test mode' 15 430 95
$cmbAudioTransportMode = New-Object System.Windows.Forms.ComboBox
$cmbAudioTransportMode.Location = New-Object System.Drawing.Point(115, 354)
$cmbAudioTransportMode.Size = New-Object System.Drawing.Size(245, 23)
$cmbAudioTransportMode.DropDownStyle = 'DropDownList'
$null = $cmbAudioTransportMode.Items.AddRange([string[]]@(
    'Normal audio',
    'Video only - no audio track',
    'Muted audio clock only'
))
$cmbAudioTransportMode.SelectedItem = $script:DefaultAudioTransportMode
$settingsGroup.Controls.Add($cmbAudioTransportMode)
$toolTip.SetToolTip($cmbAudioTransportMode, 'A/V sync diagnostic. Normal uses the checkboxes below. Video only removes the audio track. Muted audio clock keeps an audio clock but emits silence.')

$cmbSplitAudioPipelineClockMode = New-Object System.Windows.Forms.ComboBox
$cmbSplitAudioPipelineClockMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbSplitAudioPipelineClockMode.Size = New-Object System.Drawing.Size(225, 23)
$cmbSplitAudioPipelineClockMode.DropDownStyle = 'DropDownList'
$null = $cmbSplitAudioPipelineClockMode.Items.AddRange([string[]]@(
    'Follow video/master',
    'Automatic / element elected',
    'System monotonic',
    'System realtime'
))
$cmbSplitAudioPipelineClockMode.SelectedItem = $script:DefaultSplitAudioPipelineClockMode
$settingsGroup.Controls.Add($cmbSplitAudioPipelineClockMode)
$toolTip.SetToolTip($cmbSplitAudioPipelineClockMode, 'Clock for the separate split-audio gst-launch process. Single-pipeline A/V always uses the master clock selected on the Video tab. Follow video/master applies the same selection to split audio.')

$lblAudioClockMode = Add-Label $settingsGroup 'WASAPI provider' 15 548 110

$cmbAudioClockMode = New-Object System.Windows.Forms.ComboBox
$cmbAudioClockMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbAudioClockMode.Size = New-Object System.Drawing.Size(230, 23)
$cmbAudioClockMode.DropDownStyle = 'DropDownList'
$null = $cmbAudioClockMode.Items.AddRange([string[]]@('Plugin default / allow WASAPI clock','System clock / no WASAPI clock'))
$cmbAudioClockMode.SelectedItem = $script:DefaultAudioClockMode
$settingsGroup.Controls.Add($cmbAudioClockMode)
$toolTip.SetToolTip($cmbAudioClockMode, 'Plugin default emits no provide-clock property. System clock / no WASAPI clock explicitly appends provide-clock=false. For a monotonic-master test, also select System monotonic on the Video tab and Resample as the slave method.')

$lblAudioTimingMode = Add-Label $settingsGroup 'Audio timing' 15 602 95
$cmbAudioTimingMode = New-Object System.Windows.Forms.ComboBox
$cmbAudioTimingMode.Location = New-Object System.Drawing.Point(115, 602)
$cmbAudioTimingMode.Size = New-Object System.Drawing.Size(260, 23)
$cmbAudioTimingMode.DropDownStyle = 'DropDownList'
$null = $cmbAudioTimingMode.Items.AddRange([string[]]@(
    'Plugin default / WASAPI normal',
    'WASAPI no pipeline clock',
    'WASAPI retimestamp',
    'WASAPI no clock + retimestamp',
    'Synthetic silent audio'
))
$cmbAudioTimingMode.SelectedItem = $script:DefaultAudioTimingMode
$settingsGroup.Controls.Add($cmbAudioTimingMode)
$toolTip.SetToolTip($cmbAudioTimingMode, 'Plugin default emits no do-timestamp or clock override. Synthetic silent audio bypasses WASAPI; the other entries explicitly add the named timing behavior.')

$lblAudioSlaveMethod = Add-Label $settingsGroup 'Slave method' 395 602 95
$cmbAudioSlaveMethod = New-Object System.Windows.Forms.ComboBox
$cmbAudioSlaveMethod.Location = New-Object System.Drawing.Point(495, 602)
$cmbAudioSlaveMethod.Size = New-Object System.Drawing.Size(135, 23)
$cmbAudioSlaveMethod.DropDownStyle = 'DropDownList'
$null = $cmbAudioSlaveMethod.Items.AddRange([string[]]@('Auto','None','Skew','Resample','Retimestamp'))
$cmbAudioSlaveMethod.SelectedItem = $script:DefaultAudioSlaveMethod
$settingsGroup.Controls.Add($cmbAudioSlaveMethod)
$toolTip.SetToolTip($cmbAudioSlaveMethod, 'Experimental wasapi2src/audiobasesrc slave-method. Leave Auto unless testing clock drift.')

$cmbAudioSyncMode = New-Object System.Windows.Forms.ComboBox
$cmbAudioSyncMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbAudioSyncMode.Size = New-Object System.Drawing.Size(120, 23)
$cmbAudioSyncMode.DropDownStyle = 'DropDownList'
$null = $cmbAudioSyncMode.Items.AddRange([string[]]@('Default','sync=true','sync=false'))
$cmbAudioSyncMode.SelectedItem = $script:DefaultAudioSyncMode
$settingsGroup.Controls.Add($cmbAudioSyncMode)
$toolTip.SetToolTip($cmbAudioSyncMode, 'Audio branch sync lab. Default leaves audio send branches unchanged. sync=true/sync=false inserts a clocksync element before compatible send/mux sinks so we can test whether sender-side timestamp scheduling is coupling A/V latency.')

$chkWasapiLowLatencyOverride = New-Object System.Windows.Forms.CheckBox
$chkWasapiLowLatencyOverride.Text = 'Force low-latency=true'
$chkWasapiLowLatencyOverride.Location = New-Object System.Drawing.Point(650, 602)
$chkWasapiLowLatencyOverride.Size = New-Object System.Drawing.Size(175, 23)
$chkWasapiLowLatencyOverride.Checked = $script:DefaultWasapiLowLatencyOverride
$settingsGroup.Controls.Add($chkWasapiLowLatencyOverride)
$toolTip.SetToolTip($chkWasapiLowLatencyOverride, 'Unchecked emits no low-latency property and leaves the WASAPI source at its plugin default. Checked explicitly appends low-latency=true.')

$chkAudioBufferOverride = New-Object System.Windows.Forms.CheckBox
$chkAudioBufferOverride.Text = 'Override buffer-time'
$chkAudioBufferOverride.Location = New-Object System.Drawing.Point(365, 648)
$chkAudioBufferOverride.Size = New-Object System.Drawing.Size(155, 23)
$chkAudioBufferOverride.Checked = $script:DefaultAudioBufferOverride
$settingsGroup.Controls.Add($chkAudioBufferOverride)
$toolTip.SetToolTip($chkAudioBufferOverride, 'Unchecked emits no buffer-time property. Checked explicitly appends buffer-time using the Buffer ms value.')

$chkAudioLatencyOverride = New-Object System.Windows.Forms.CheckBox
$chkAudioLatencyOverride.Text = 'Override latency-time'
$chkAudioLatencyOverride.Location = New-Object System.Drawing.Point(525, 648)
$chkAudioLatencyOverride.Size = New-Object System.Drawing.Size(155, 23)
$chkAudioLatencyOverride.Checked = $script:DefaultAudioLatencyOverride
$settingsGroup.Controls.Add($chkAudioLatencyOverride)
$toolTip.SetToolTip($chkAudioLatencyOverride, 'Unchecked emits no latency-time property. Checked explicitly appends latency-time using the Latency ms value.')

$lblAudioBufferMs = Add-Label $settingsGroup 'Buffer ms' 15 648 80
$numAudioBufferMs = New-Object System.Windows.Forms.NumericUpDown
$numAudioBufferMs.Location = New-Object System.Drawing.Point(95, 648)
$numAudioBufferMs.Size = New-Object System.Drawing.Size(75, 23)
$numAudioBufferMs.Minimum = 1
$numAudioBufferMs.Maximum = 1000
$numAudioBufferMs.Value = $script:DefaultAudioBufferMs
$settingsGroup.Controls.Add($numAudioBufferMs)
$toolTip.SetToolTip($numAudioBufferMs, 'WASAPI buffer-time in milliseconds. This value is emitted only while Override buffer-time is checked.')

$lblAudioLatencyMs = Add-Label $settingsGroup 'Latency ms' 195 648 80
$numAudioLatencyMs = New-Object System.Windows.Forms.NumericUpDown
$numAudioLatencyMs.Location = New-Object System.Drawing.Point(275, 648)
$numAudioLatencyMs.Size = New-Object System.Drawing.Size(75, 23)
$numAudioLatencyMs.Minimum = 1
$numAudioLatencyMs.Maximum = 1000
$numAudioLatencyMs.Value = $script:DefaultAudioLatencyMs
$settingsGroup.Controls.Add($numAudioLatencyMs)

$chkAudioSampleRateOverride = New-Object System.Windows.Forms.CheckBox
$chkAudioSampleRateOverride.Text = 'Override sample rate'
$chkAudioSampleRateOverride.Location = New-Object System.Drawing.Point(15, 694)
$chkAudioSampleRateOverride.Size = New-Object System.Drawing.Size(170, 23)
$chkAudioSampleRateOverride.Checked = $script:DefaultAudioSampleRateOverride
$settingsGroup.Controls.Add($chkAudioSampleRateOverride)
$toolTip.SetToolTip($chkAudioSampleRateOverride, 'Unchecked emits no rate field in raw-audio caps and leaves sample-rate negotiation to GStreamer. Checked forces the selected processing rate on desktop, microphone, audiomixer output, split audio, and recording audio paths.')

$lblAudioSampleRate = Add-Label $settingsGroup 'Rate Hz' 190 694 60
$numAudioSampleRate = New-Object System.Windows.Forms.NumericUpDown
$numAudioSampleRate.Location = New-Object System.Drawing.Point(250, 694)
$numAudioSampleRate.Size = New-Object System.Drawing.Size(100, 23)
$numAudioSampleRate.Minimum = 8000
$numAudioSampleRate.Maximum = 192000
$numAudioSampleRate.Increment = 100
$numAudioSampleRate.Value = $script:DefaultAudioSampleRate
$numAudioSampleRate.Enabled = $script:DefaultAudioSampleRateOverride
$settingsGroup.Controls.Add($numAudioSampleRate)
$toolTip.SetToolTip($numAudioSampleRate, 'Raw-audio processing rate in Hz. Opus accepts 8000, 12000, 16000, 24000, or 48000 Hz; other explicit values may be useful for non-Opus codec experiments and may intentionally fail with Opus.')
$toolTip.SetToolTip($numAudioLatencyMs, 'WASAPI latency-time in milliseconds. This value is emitted only while Override latency-time is checked.')

$null = Add-Label $settingsGroup 'Audio codec' 15 354 80
$cmbAudioCodec = New-Object System.Windows.Forms.ComboBox
$cmbAudioCodec.Location = New-Object System.Drawing.Point(95, 354)
$cmbAudioCodec.Size = New-Object System.Drawing.Size(210, 23)
$cmbAudioCodec.DropDownStyle = 'DropDownList'
$settingsGroup.Controls.Add($cmbAudioCodec)
$toolTip.SetToolTip($cmbAudioCodec, 'A compatible selection is remembered independently for each protocol.')

$lblAudioCodecStatus = New-Object System.Windows.Forms.Label
$lblAudioCodecStatus.Text = 'Protocol default'
$lblAudioCodecStatus.Location = New-Object System.Drawing.Point(315, 354)
$lblAudioCodecStatus.Size = New-Object System.Drawing.Size(245, 23)
$lblAudioCodecStatus.TextAlign = 'MiddleLeft'
$lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblAudioCodecStatus)

$null = Add-Label $settingsGroup 'Audio kbps' 570 354 75
$numAudioBitrate = New-Object System.Windows.Forms.NumericUpDown
$numAudioBitrate.Location = New-Object System.Drawing.Point(645, 354)
$numAudioBitrate.Size = New-Object System.Drawing.Size(70, 23)
$numAudioBitrate.Minimum = 32
$numAudioBitrate.Maximum = 512
$numAudioBitrate.Increment = 16
$numAudioBitrate.Value = 128
$settingsGroup.Controls.Add($numAudioBitrate)

$cmbDirectWebRtcOpusMode = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcOpusMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcOpusMode.Size = New-Object System.Drawing.Size(190, 23)
$cmbDirectWebRtcOpusMode.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcOpusMode.Items.AddRange([string[]]@('Explicit Opus encoder','Raw audio to webrtcsink'))
$cmbDirectWebRtcOpusMode.SelectedItem = $script:DefaultDirectWebRtcOpusMode
$settingsGroup.Controls.Add($cmbDirectWebRtcOpusMode)
$toolTip.SetToolTip($cmbDirectWebRtcOpusMode, 'Direct GST WebRTC audio path. Explicit Opus exposes frame-size/type/FEC/DTX. Raw audio hands S16LE to webrtcsink and lets it spawn its own internal encoder.')

$cmbDirectWebRtcOpusFrameMs = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcOpusFrameMs.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcOpusFrameMs.Size = New-Object System.Drawing.Size(85, 23)
$cmbDirectWebRtcOpusFrameMs.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcOpusFrameMs.Items.AddRange([string[]]@('2.5','5','10','20','40','60'))
$cmbDirectWebRtcOpusFrameMs.SelectedItem = $script:DefaultDirectWebRtcOpusFrameMs
$settingsGroup.Controls.Add($cmbDirectWebRtcOpusFrameMs)
$toolTip.SetToolTip($cmbDirectWebRtcOpusFrameMs, 'opusenc frame-size for Direct GST WebRTC when Explicit Opus encoder is selected. Smaller frames reduce fixed audio encode delay but increase packet rate.')

$cmbDirectWebRtcOpusAudioType = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcOpusAudioType.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcOpusAudioType.Size = New-Object System.Drawing.Size(170, 23)
$cmbDirectWebRtcOpusAudioType.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcOpusAudioType.Items.AddRange([string[]]@('restricted-lowdelay','voice','generic'))
$cmbDirectWebRtcOpusAudioType.SelectedItem = $script:DefaultDirectWebRtcOpusAudioType
$settingsGroup.Controls.Add($cmbDirectWebRtcOpusAudioType)
$toolTip.SetToolTip($cmbDirectWebRtcOpusAudioType, 'opusenc audio-type for Direct GST WebRTC explicit Opus encoding.')

$chkDirectWebRtcOpusFec = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcOpusFec.Text = 'Opus FEC'
$chkDirectWebRtcOpusFec.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcOpusFec.Size = New-Object System.Drawing.Size(95, 23)
$chkDirectWebRtcOpusFec.Checked = $script:DefaultDirectWebRtcOpusFec
$settingsGroup.Controls.Add($chkDirectWebRtcOpusFec)
$toolTip.SetToolTip($chkDirectWebRtcOpusFec, 'opusenc inband-fec for Direct GST WebRTC. Keep off for lowest LAN latency unless testing packet loss recovery.')

$chkDirectWebRtcOpusDtx = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcOpusDtx.Text = 'Opus DTX'
$chkDirectWebRtcOpusDtx.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcOpusDtx.Size = New-Object System.Drawing.Size(95, 23)
$chkDirectWebRtcOpusDtx.Checked = $script:DefaultDirectWebRtcOpusDtx
$settingsGroup.Controls.Add($chkDirectWebRtcOpusDtx)
$toolTip.SetToolTip($chkDirectWebRtcOpusDtx, 'opusenc dtx for Direct GST WebRTC. Usually off for desktop/game streaming so silence does not change receiver timing behavior.')

$audioNote = New-Object System.Windows.Forms.Label
$audioNote.Text = 'A/V test mode isolates desync: Video only removes audio; Muted audio clock keeps GstAudioSrcClock but sends silence. Normal uses WASAPI loopback/mic.'
$audioNote.Location = New-Object System.Drawing.Point(15, 392)
$audioNote.Size = New-Object System.Drawing.Size(700, 22)
$audioNote.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($audioNote)

$protocolNote = New-Object System.Windows.Forms.Label
$protocolNote.Text = 'Audio defaults: WHIP/SRT/RTSP use Opus; RTMP uses AAC. SRT uses PID 256/257, program 1, 2.9 ms mux sync.'
$protocolNote.Location = New-Object System.Drawing.Point(15, 418)
$protocolNote.Size = New-Object System.Drawing.Size(700, 22)
$protocolNote.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($protocolNote)

$latencyNote = New-Object System.Windows.Forms.Label
$latencyNote.Text = 'Low-latency defaults: B-frames 0, look-ahead off, AQ off, 1-second GOP, and leaky queues. Controls enable only where supported.'
$latencyNote.Location = New-Object System.Drawing.Point(15, 446)
$latencyNote.Size = New-Object System.Drawing.Size(700, 38)
$latencyNote.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($latencyNote)

$changesNote = New-Object System.Windows.Forms.Label
$changesNote.Text = 'Changes apply on the next Start or Restart Pipeline.'
$changesNote.Location = New-Object System.Drawing.Point(15, 492)
$changesNote.Size = New-Object System.Drawing.Size(700, 22)
$changesNote.ForeColor = [System.Drawing.Color]::DarkSlateBlue
$settingsGroup.Controls.Add($changesNote)

$chkStartMediaMtx = New-Object System.Windows.Forms.CheckBox
$chkStartMediaMtx.Text = 'Start/stop MediaMTX with stream'
$chkStartMediaMtx.Location = New-Object System.Drawing.Point(15, 546)
$chkStartMediaMtx.Size = New-Object System.Drawing.Size(220, 25)
$chkStartMediaMtx.Checked = $false
$settingsGroup.Controls.Add($chkStartMediaMtx)
$toolTip.SetToolTip(
    $chkStartMediaMtx,
    'Starts MediaMTX before GStreamer and stops it whenever the stream stops or restarts. Only the MediaMTX process started by this application is terminated.'
)

$txtMediaMtxPath = New-Object System.Windows.Forms.TextBox
$txtMediaMtxPath.Location = New-Object System.Drawing.Point(240, 546)
$txtMediaMtxPath.Size = New-Object System.Drawing.Size(400, 23)
$txtMediaMtxPath.Text = Find-MediaMtx
$settingsGroup.Controls.Add($txtMediaMtxPath)
$toolTip.SetToolTip(
    $txtMediaMtxPath,
    'Path to mediamtx.exe. It is launched hidden with its working directory set to the executable folder so mediamtx.yml beside it is discovered normally.'
)

$btnBrowseMediaMtx = New-Object System.Windows.Forms.Button
$btnBrowseMediaMtx.Text = 'Browse...'
$btnBrowseMediaMtx.Location = New-Object System.Drawing.Point(650, 544)
$btnBrowseMediaMtx.Size = New-Object System.Drawing.Size(68, 27)
$settingsGroup.Controls.Add($btnBrowseMediaMtx)


$defaultRecordingRoot = [Environment]::GetFolderPath('MyVideos')
if ([string]::IsNullOrWhiteSpace($defaultRecordingRoot)) {
    $defaultRecordingRoot = [Environment]::GetFolderPath('Desktop')
}
if ([string]::IsNullOrWhiteSpace($defaultRecordingRoot)) {
    $defaultRecordingRoot = $env:USERPROFILE
}
$defaultRecordingDirectory = Join-Path $defaultRecordingRoot 'GStreamer Glass'

$chkRecordingEnabled = New-Object System.Windows.Forms.CheckBox
$chkRecordingEnabled.Text = 'Enable recording'
$chkRecordingEnabled.Location = New-Object System.Drawing.Point(15, 520)
$chkRecordingEnabled.Size = New-Object System.Drawing.Size(160, 23)
$chkRecordingEnabled.Checked = $false
$settingsGroup.Controls.Add($chkRecordingEnabled)
$toolTip.SetToolTip($chkRecordingEnabled, 'Enables the recording controls and encoder settings. It does not start recording by itself.')

$chkRecordWithStream = New-Object System.Windows.Forms.CheckBox
$chkRecordWithStream.Text = 'Record with stream'
$chkRecordWithStream.Location = New-Object System.Drawing.Point(180, 520)
$chkRecordWithStream.Size = New-Object System.Drawing.Size(160, 23)
$chkRecordWithStream.Checked = $false
$settingsGroup.Controls.Add($chkRecordWithStream)
$toolTip.SetToolTip($chkRecordWithStream, 'Automatically includes the recording branch whenever Go Live starts a transport stream. Preview-only pipelines never record.')

$btnToggleRecording = New-Object System.Windows.Forms.Button
$btnToggleRecording.Text = 'Start Recording'
$btnToggleRecording.Location = New-Object System.Drawing.Point(350, 516)
$btnToggleRecording.Size = New-Object System.Drawing.Size(145, 29)
$btnToggleRecording.Enabled = $false
$settingsGroup.Controls.Add($btnToggleRecording)
$toolTip.SetToolTip($btnToggleRecording, 'Starts or stops recording explicitly. While live, applying the change restarts the stream so the recording branch can be added or removed safely.')

$txtRecordingDirectory = New-Object System.Windows.Forms.TextBox
$txtRecordingDirectory.Location = New-Object System.Drawing.Point(15, 548)
$txtRecordingDirectory.Size = New-Object System.Drawing.Size(500, 23)
$txtRecordingDirectory.Text = $defaultRecordingDirectory
$settingsGroup.Controls.Add($txtRecordingDirectory)
$toolTip.SetToolTip($txtRecordingDirectory, 'Folder where recording files are written. The folder is created on Start if needed.')

$btnBrowseRecordingDirectory = New-Object System.Windows.Forms.Button
$btnBrowseRecordingDirectory.Text = 'Browse...'
$btnBrowseRecordingDirectory.Location = New-Object System.Drawing.Point(525, 546)
$btnBrowseRecordingDirectory.Size = New-Object System.Drawing.Size(90, 27)
$settingsGroup.Controls.Add($btnBrowseRecordingDirectory)

$txtRecordingTemplate = New-Object System.Windows.Forms.TextBox
$txtRecordingTemplate.Location = New-Object System.Drawing.Point(15, 548)
$txtRecordingTemplate.Size = New-Object System.Drawing.Size(500, 23)
$txtRecordingTemplate.Text = 'Glass-{yyyyMMdd-HHmmss}-{protocol}-{width}x{height}-{fps}fps.mkv'
$settingsGroup.Controls.Add($txtRecordingTemplate)
$toolTip.SetToolTip($txtRecordingTemplate, 'File name template. Supports {yyyyMMdd-HHmmss}, {date}, {time}, {protocol}, {encoder}, {width}, {height}, and {fps}.')

$cmbRecordingEncoder = New-Object System.Windows.Forms.ComboBox
$cmbRecordingEncoder.Location = New-Object System.Drawing.Point(15, 548)
$cmbRecordingEncoder.Size = New-Object System.Drawing.Size(360, 23)
$cmbRecordingEncoder.DropDownStyle = 'DropDownList'
$null = $cmbRecordingEncoder.Items.AddRange([string[]]($script:EncoderCatalog.Keys))
$cmbRecordingEncoder.SelectedItem = $script:DefaultEncoderName
$settingsGroup.Controls.Add($cmbRecordingEncoder)
$toolTip.SetToolTip($cmbRecordingEncoder, 'Recording uses its own encoder and bitrate so the stream can stay low-latency while the file gets a different quality target.')

$lblRecordingStatus = New-Object System.Windows.Forms.Label
$lblRecordingStatus.Text = 'Recording disabled'
$lblRecordingStatus.Location = New-Object System.Drawing.Point(390, 548)
$lblRecordingStatus.Size = New-Object System.Drawing.Size(325, 23)
$lblRecordingStatus.TextAlign = 'MiddleLeft'
$lblRecordingStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblRecordingStatus)

$cmbRecordingPreset = New-Object System.Windows.Forms.ComboBox
$cmbRecordingPreset.Location = New-Object System.Drawing.Point(15, 548)
$cmbRecordingPreset.Size = New-Object System.Drawing.Size(100, 23)
$cmbRecordingPreset.DropDownStyle = 'DropDownList'
$null = $cmbRecordingPreset.Items.AddRange(@('p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'))
$cmbRecordingPreset.SelectedItem = 'p5'
$settingsGroup.Controls.Add($cmbRecordingPreset)

$cmbRecordingProfile = New-Object System.Windows.Forms.ComboBox
$cmbRecordingProfile.Location = New-Object System.Drawing.Point(15, 548)
$cmbRecordingProfile.Size = New-Object System.Drawing.Size(150, 23)
$cmbRecordingProfile.DropDownStyle = 'DropDownList'
$null = $cmbRecordingProfile.Items.AddRange(@('constrained-baseline', 'baseline', 'main', 'high'))
$cmbRecordingProfile.SelectedItem = 'high'
$settingsGroup.Controls.Add($cmbRecordingProfile)

$numRecordingWidth = New-Object System.Windows.Forms.NumericUpDown
$numRecordingWidth.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingWidth.Size = New-Object System.Drawing.Size(90, 23)
$numRecordingWidth.Minimum = 320
$numRecordingWidth.Maximum = 7680
$numRecordingWidth.Increment = 16
$numRecordingWidth.Value = 1920
$settingsGroup.Controls.Add($numRecordingWidth)

$numRecordingHeight = New-Object System.Windows.Forms.NumericUpDown
$numRecordingHeight.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingHeight.Size = New-Object System.Drawing.Size(90, 23)
$numRecordingHeight.Minimum = 240
$numRecordingHeight.Maximum = 4320
$numRecordingHeight.Increment = 16
$numRecordingHeight.Value = 1080
$settingsGroup.Controls.Add($numRecordingHeight)

$numRecordingFps = New-Object System.Windows.Forms.NumericUpDown
$numRecordingFps.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingFps.Size = New-Object System.Drawing.Size(80, 23)
$numRecordingFps.Minimum = 1
$numRecordingFps.Maximum = 240
$numRecordingFps.Value = 60
$settingsGroup.Controls.Add($numRecordingFps)

$numRecordingVideoBitrate = New-Object System.Windows.Forms.NumericUpDown
$numRecordingVideoBitrate.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingVideoBitrate.Size = New-Object System.Drawing.Size(110, 23)
$numRecordingVideoBitrate.Minimum = 250
$numRecordingVideoBitrate.Maximum = 200000
$numRecordingVideoBitrate.Increment = 500
$numRecordingVideoBitrate.Value = 25000
$settingsGroup.Controls.Add($numRecordingVideoBitrate)


$cmbRecordingRateControl = New-Object System.Windows.Forms.ComboBox
$cmbRecordingRateControl.Location = New-Object System.Drawing.Point(15, 548)
$cmbRecordingRateControl.Size = New-Object System.Drawing.Size(95, 23)
$cmbRecordingRateControl.DropDownStyle = 'DropDownList'
$null = $cmbRecordingRateControl.Items.AddRange([string[]]$script:RateControlModes)
$cmbRecordingRateControl.SelectedItem = 'constqp'
$settingsGroup.Controls.Add($cmbRecordingRateControl)
$toolTip.SetToolTip($cmbRecordingRateControl, 'Recording rate control. constqp is the OBS-style quality-first default; CBR/VBR remain available.')

$numRecordingMaxVideoBitrate = New-Object System.Windows.Forms.NumericUpDown
$numRecordingMaxVideoBitrate.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingMaxVideoBitrate.Size = New-Object System.Drawing.Size(100, 23)
$numRecordingMaxVideoBitrate.Minimum = 0
$numRecordingMaxVideoBitrate.Maximum = 500000
$numRecordingMaxVideoBitrate.Increment = 500
$numRecordingMaxVideoBitrate.Value = 0
$settingsGroup.Controls.Add($numRecordingMaxVideoBitrate)
$toolTip.SetToolTip($numRecordingMaxVideoBitrate, 'Recording maximum bitrate for VBR where supported. 0 uses encoder default.')

$numRecordingConstantQp = New-Object System.Windows.Forms.NumericUpDown
$numRecordingConstantQp.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingConstantQp.Size = New-Object System.Drawing.Size(70, 23)
$numRecordingConstantQp.Minimum = 0
$numRecordingConstantQp.Maximum = 51
$numRecordingConstantQp.Value = 20
$settingsGroup.Controls.Add($numRecordingConstantQp)
$toolTip.SetToolTip($numRecordingConstantQp, 'Recording CQ/QP. Lower means higher quality and larger files. 18-23 is usually the useful range for H.264/H.265 testing.')

$numRecordingGopSeconds = New-Object System.Windows.Forms.NumericUpDown
$numRecordingGopSeconds.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingGopSeconds.Size = New-Object System.Drawing.Size(80, 23)
$numRecordingGopSeconds.Minimum = 1
$numRecordingGopSeconds.Maximum = 10
$numRecordingGopSeconds.Value = 2
$settingsGroup.Controls.Add($numRecordingGopSeconds)

$numRecordingBFrames = New-Object System.Windows.Forms.NumericUpDown
$numRecordingBFrames.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingBFrames.Size = New-Object System.Drawing.Size(80, 23)
$numRecordingBFrames.Minimum = 0
$numRecordingBFrames.Maximum = 4
$numRecordingBFrames.Value = 2
$settingsGroup.Controls.Add($numRecordingBFrames)
$toolTip.SetToolTip($numRecordingBFrames, 'Recording can use B-frames for quality because this branch is not the live WebRTC path.')


$cmbRecordingTune = New-Object System.Windows.Forms.ComboBox
$cmbRecordingTune.Location = New-Object System.Drawing.Point(15, 548)
$cmbRecordingTune.Size = New-Object System.Drawing.Size(165, 23)
$cmbRecordingTune.DropDownStyle = 'DropDownList'
$null = $cmbRecordingTune.Items.AddRange([string[]]$script:NvencTuneModes)
$cmbRecordingTune.SelectedItem = 'high-quality'
$settingsGroup.Controls.Add($cmbRecordingTune)
$toolTip.SetToolTip($cmbRecordingTune, 'NVENC tune for recording. high-quality is the default; use low-latency/ultra-low-latency only when recording must stay realtime above quality.')

$cmbRecordingMultipass = New-Object System.Windows.Forms.ComboBox
$cmbRecordingMultipass.Location = New-Object System.Drawing.Point(15, 548)
$cmbRecordingMultipass.Size = New-Object System.Drawing.Size(150, 23)
$cmbRecordingMultipass.DropDownStyle = 'DropDownList'
$null = $cmbRecordingMultipass.Items.AddRange([string[]]$script:NvencMultipassModes)
$cmbRecordingMultipass.SelectedItem = 'two-pass-quarter'
$settingsGroup.Controls.Add($cmbRecordingMultipass)
$toolTip.SetToolTip($cmbRecordingMultipass, 'NVENC multipass for recording. two-pass-quarter mirrors OBS-style quality without full two-pass cost.')

$chkRecordingLookAhead = New-Object System.Windows.Forms.CheckBox
$chkRecordingLookAhead.Text = 'Look-ahead'
$chkRecordingLookAhead.Location = New-Object System.Drawing.Point(15, 548)
$chkRecordingLookAhead.Size = New-Object System.Drawing.Size(105, 23)
$chkRecordingLookAhead.Checked = $false
$settingsGroup.Controls.Add($chkRecordingLookAhead)
$toolTip.SetToolTip($chkRecordingLookAhead, 'Recording look-ahead where supported. Adds frame buffering but can improve B-frame decisions/quality.')

$numRecordingLookAheadFrames = New-Object System.Windows.Forms.NumericUpDown
$numRecordingLookAheadFrames.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingLookAheadFrames.Size = New-Object System.Drawing.Size(70, 23)
$numRecordingLookAheadFrames.Minimum = 1
$numRecordingLookAheadFrames.Maximum = 64
$numRecordingLookAheadFrames.Value = 20
$numRecordingLookAheadFrames.Enabled = $false
$settingsGroup.Controls.Add($numRecordingLookAheadFrames)

$chkRecordingSpatialAq = New-Object System.Windows.Forms.CheckBox
$chkRecordingSpatialAq.Text = 'Spatial AQ'
$chkRecordingSpatialAq.Location = New-Object System.Drawing.Point(15, 548)
$chkRecordingSpatialAq.Size = New-Object System.Drawing.Size(90, 23)
$chkRecordingSpatialAq.Checked = $true
$settingsGroup.Controls.Add($chkRecordingSpatialAq)

$chkRecordingTemporalAq = New-Object System.Windows.Forms.CheckBox
$chkRecordingTemporalAq.Text = 'Temporal AQ'
$chkRecordingTemporalAq.Location = New-Object System.Drawing.Point(15, 548)
$chkRecordingTemporalAq.Size = New-Object System.Drawing.Size(105, 23)
$chkRecordingTemporalAq.Checked = $true
$settingsGroup.Controls.Add($chkRecordingTemporalAq)

$numRecordingAqStrength = New-Object System.Windows.Forms.NumericUpDown
$numRecordingAqStrength.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingAqStrength.Size = New-Object System.Drawing.Size(70, 23)
$numRecordingAqStrength.Minimum = 1
$numRecordingAqStrength.Maximum = 15
$numRecordingAqStrength.Value = 8
$settingsGroup.Controls.Add($numRecordingAqStrength)

$numRecordingVbvBuffer = New-Object System.Windows.Forms.NumericUpDown
$numRecordingVbvBuffer.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingVbvBuffer.Size = New-Object System.Drawing.Size(100, 23)
$numRecordingVbvBuffer.Minimum = 0
$numRecordingVbvBuffer.Maximum = 1000000
$numRecordingVbvBuffer.Increment = 500
$numRecordingVbvBuffer.Value = 0
$settingsGroup.Controls.Add($numRecordingVbvBuffer)
$toolTip.SetToolTip($numRecordingVbvBuffer, 'NVENC VBV/HRD buffer size in kbits. 0 uses encoder default.')

$txtRecordingCustomEncoderOptions = New-Object System.Windows.Forms.TextBox
$txtRecordingCustomEncoderOptions.Location = New-Object System.Drawing.Point(15, 548)
$txtRecordingCustomEncoderOptions.Size = New-Object System.Drawing.Size(520, 23)
$txtRecordingCustomEncoderOptions.Text = ''
$settingsGroup.Controls.Add($txtRecordingCustomEncoderOptions)
$toolTip.SetToolTip($txtRecordingCustomEncoderOptions, 'Raw options appended directly after the selected recording encoder element. Useful for AMD/Intel/MF/software knobs while we validate mappings.')

$chkRecordingDesktopAudio = New-Object System.Windows.Forms.CheckBox
$chkRecordingDesktopAudio.Text = 'Record desktop audio'
$chkRecordingDesktopAudio.Location = New-Object System.Drawing.Point(15, 548)
$chkRecordingDesktopAudio.Size = New-Object System.Drawing.Size(170, 23)
$chkRecordingDesktopAudio.Checked = $true
$settingsGroup.Controls.Add($chkRecordingDesktopAudio)

$chkRecordingMic = New-Object System.Windows.Forms.CheckBox
$chkRecordingMic.Text = 'Record microphone'
$chkRecordingMic.Location = New-Object System.Drawing.Point(15, 548)
$chkRecordingMic.Size = New-Object System.Drawing.Size(170, 23)
$chkRecordingMic.Checked = $false
$settingsGroup.Controls.Add($chkRecordingMic)

$numRecordingAudioBitrate = New-Object System.Windows.Forms.NumericUpDown
$numRecordingAudioBitrate.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingAudioBitrate.Size = New-Object System.Drawing.Size(100, 23)
$numRecordingAudioBitrate.Minimum = 32
$numRecordingAudioBitrate.Maximum = 512
$numRecordingAudioBitrate.Increment = 16
$numRecordingAudioBitrate.Value = 192
$settingsGroup.Controls.Add($numRecordingAudioBitrate)

$previewGroup = New-Object System.Windows.Forms.GroupBox
$previewGroup.Text = 'Local Preview (experimental)'
$previewGroup.Location = New-Object System.Drawing.Point(755, 10)
$previewGroup.Size = New-Object System.Drawing.Size(440, 586)
$previewGroup.Anchor = 'Top,Right'
$form.Controls.Add($previewGroup)

$previewPanel = New-Object System.Windows.Forms.Panel
$previewPanel.Location = New-Object System.Drawing.Point(12, 24)
$previewPanel.Size = New-Object System.Drawing.Size(416, 544)
$previewPanel.BackColor = [System.Drawing.Color]::Black
$previewPanel.Anchor = 'Top,Bottom,Left,Right'
$previewGroup.Controls.Add($previewPanel)

$previewPlaceholder = New-Object System.Windows.Forms.Label
$previewPlaceholder.Text = 'Preview disabled for this pipeline'
$previewPlaceholder.ForeColor = [System.Drawing.Color]::LightGray
$previewPlaceholder.BackColor = [System.Drawing.Color]::Black
$previewPlaceholder.TextAlign = 'MiddleCenter'
$previewPlaceholder.Dock = 'Fill'
$previewPanel.Controls.Add($previewPlaceholder)

$lowerTabs = New-Object System.Windows.Forms.TabControl
$lowerTabs.Location = New-Object System.Drawing.Point(10, 650)
$lowerTabs.Size = New-Object System.Drawing.Size(1185, 396)
$lowerTabs.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($lowerTabs)

$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Text = 'Output Log'
$tabLog.Padding = New-Object System.Windows.Forms.Padding(6)
$null = $lowerTabs.TabPages.Add($tabLog)

$tabCommand = New-Object System.Windows.Forms.TabPage
$tabCommand.Text = 'Generated Command'
$tabCommand.Padding = New-Object System.Windows.Forms.Padding(6)
$null = $lowerTabs.TabPages.Add($tabCommand)

$tabCustomGstArgs = New-Object System.Windows.Forms.TabPage
$tabCustomGstArgs.Text = 'Custom Args'
$tabCustomGstArgs.Padding = New-Object System.Windows.Forms.Padding(6, 6, 10, 6)
$null = $lowerTabs.TabPages.Add($tabCustomGstArgs)

# Appends no longer force a scroll while the log tab is hidden, so catch the
# tail up whenever the log becomes visible again.
$lowerTabs.Add_SelectedIndexChanged({
    if ($lowerTabs.SelectedTab -eq $tabLog) {
        Scroll-LogToBottom
    }
})

$txtCommand = New-Object System.Windows.Forms.TextBox
$txtCommand.Multiline = $true
$txtCommand.ScrollBars = 'Vertical'
$txtCommand.WordWrap = $true
$txtCommand.ReadOnly = $true
$txtCommand.HideSelection = $false
$txtCommand.AcceptsReturn = $false
$txtCommand.AcceptsTab = $false
$txtCommand.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtCommand.Dock = 'Fill'
$tabCommand.Controls.Add($txtCommand)

$customArgsTopPanel = New-Object System.Windows.Forms.Panel
$customArgsTopPanel.Dock = 'Top'
$customArgsTopPanel.Height = 76
$tabCustomGstArgs.Controls.Add($customArgsTopPanel)

$customArgsButtonRow = New-Object System.Windows.Forms.FlowLayoutPanel
$customArgsButtonRow.Dock = 'Right'
$customArgsButtonRow.FlowDirection = 'RightToLeft'
$customArgsButtonRow.WrapContents = $false
$customArgsButtonRow.AutoSize = $true
$customArgsButtonRow.AutoSizeMode = 'GrowAndShrink'
$customArgsButtonRow.Margin = New-Object System.Windows.Forms.Padding(0)
$customArgsButtonRow.Padding = New-Object System.Windows.Forms.Padding(0, 6, 8, 0)
$customArgsTopPanel.Controls.Add($customArgsButtonRow)

$chkCustomGstArgumentsEnabled = New-Object System.Windows.Forms.CheckBox
$chkCustomGstArgumentsEnabled.Text = 'Use custom gst-launch args override'
$chkCustomGstArgumentsEnabled.AutoSize = $true
$chkCustomGstArgumentsEnabled.Location = New-Object System.Drawing.Point(8, 8)
$customArgsTopPanel.Controls.Add($chkCustomGstArgumentsEnabled)

$lblCustomGstArgumentsHelp = New-Object System.Windows.Forms.Label
$lblCustomGstArgumentsHelp.Text = 'Arguments only: paste everything after gst-launch-1.0.exe. Shell wrappers/operators are rejected.'
$lblCustomGstArgumentsHelp.AutoSize = $true
$lblCustomGstArgumentsHelp.Location = New-Object System.Drawing.Point(8, 38)
$customArgsTopPanel.Controls.Add($lblCustomGstArgumentsHelp)

# Docked (not Anchor+absolute-Location) so these stay correctly placed
# regardless of the panel's actual width when it's first laid out --
# Anchor='Top,Right' with a hardcoded X assumes the panel is already at its
# final docked width the moment the control is added, which it isn't yet.
$btnClearCustomGstArgs = New-Object System.Windows.Forms.Button
$btnClearCustomGstArgs.Text = 'Clear'
$btnClearCustomGstArgs.Size = New-Object System.Drawing.Size(80, 28)
$btnClearCustomGstArgs.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
$customArgsButtonRow.Controls.Add($btnClearCustomGstArgs)

$btnUseGeneratedAsCustomGstArgs = New-Object System.Windows.Forms.Button
$btnUseGeneratedAsCustomGstArgs.Text = 'Use Generated'
$btnUseGeneratedAsCustomGstArgs.Size = New-Object System.Drawing.Size(112, 28)
$btnUseGeneratedAsCustomGstArgs.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
$customArgsButtonRow.Controls.Add($btnUseGeneratedAsCustomGstArgs)

$btnPopOutCustomGstArgs = New-Object System.Windows.Forms.Button
$btnPopOutCustomGstArgs.Text = 'Pop Out'
$btnPopOutCustomGstArgs.Size = New-Object System.Drawing.Size(90, 28)
$btnPopOutCustomGstArgs.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
$toolTip.SetToolTip($btnPopOutCustomGstArgs, 'Open the custom args in a larger, resizable editor window.')
$customArgsButtonRow.Controls.Add($btnPopOutCustomGstArgs)

$txtCustomGstArguments = New-Object System.Windows.Forms.TextBox
$txtCustomGstArguments.Multiline = $true
$txtCustomGstArguments.ScrollBars = 'Vertical'
$txtCustomGstArguments.WordWrap = $true
$txtCustomGstArguments.HideSelection = $false
$txtCustomGstArguments.AcceptsReturn = $true
$txtCustomGstArguments.AcceptsTab = $true
$txtCustomGstArguments.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtCustomGstArguments.Dock = 'Fill'
$tabCustomGstArgs.Controls.Add($txtCustomGstArguments)
$customArgsTopPanel.BringToFront()

$lowerTabs.SelectedTab = $tabLog

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = 'Start Stream'
$btnStart.Location = New-Object System.Drawing.Point(10, 606)
$btnStart.Size = New-Object System.Drawing.Size(120, 34)
$btnStart.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnStart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = 'Stop'
$btnStop.Location = New-Object System.Drawing.Point(140, 606)
$btnStop.Size = New-Object System.Drawing.Size(90, 34)
$btnStop.Enabled = $false
$form.Controls.Add($btnStop)

$btnRestart = New-Object System.Windows.Forms.Button
$btnRestart.Text = 'Restart Pipeline'
$btnRestart.Location = New-Object System.Drawing.Point(240, 606)
$btnRestart.Size = New-Object System.Drawing.Size(125, 34)
$btnRestart.Enabled = $false
$form.Controls.Add($btnRestart)

$btnCopyCommand = New-Object System.Windows.Forms.Button
$btnCopyCommand.Text = 'Copy Command'
$btnCopyCommand.Location = New-Object System.Drawing.Point(375, 606)
$btnCopyCommand.Size = New-Object System.Drawing.Size(115, 34)
$form.Controls.Add($btnCopyCommand)

$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Text = 'Clear Log'
$btnClearLog.Location = New-Object System.Drawing.Point(500, 606)
$btnClearLog.Size = New-Object System.Drawing.Size(90, 34)
$form.Controls.Add($btnClearLog)

$btnOpenLogs = New-Object System.Windows.Forms.Button
$btnOpenLogs.Text = 'Open Logs'
$btnOpenLogs.Location = New-Object System.Drawing.Point(600, 606)
$btnOpenLogs.Size = New-Object System.Drawing.Size(105, 34)
$form.Controls.Add($btnOpenLogs)
$toolTip.SetToolTip(
    $btnOpenLogs,
    "Opens the optional per-run process log folder. Disk process logs are disabled by default."
)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = 'Stopped'
$statusLabel.Location = New-Object System.Drawing.Point(720, 611)
$statusLabel.Size = New-Object System.Drawing.Size(475, 25)
$statusLabel.TextAlign = 'MiddleRight'
$statusLabel.Anchor = 'Top,Right'
$statusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($statusLabel)

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip

$trayShowItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayShowItem.Text = 'Show GStreamer Glass'
$trayShowItem.Font = New-Object System.Drawing.Font($trayShowItem.Font, [System.Drawing.FontStyle]::Bold)
$null = $trayMenu.Items.Add($trayShowItem)

$null = $trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$trayStartItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayStartItem.Text = 'Start Stream'
$null = $trayMenu.Items.Add($trayStartItem)

$trayStopItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayStopItem.Text = 'Stop Stream'
$null = $trayMenu.Items.Add($trayStopItem)

$trayRestartItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayRestartItem.Text = 'Restart Pipeline'
$null = $trayMenu.Items.Add($trayRestartItem)

$null = $trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$trayExitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayExitItem.Text = 'Exit'
$null = $trayMenu.Items.Add($trayExitItem)

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = $script:AppIcon
$notifyIcon.Text = $script:AppName
$notifyIcon.ContextMenuStrip = $trayMenu
$notifyIcon.Visible = $true

$logTopPanel = New-Object System.Windows.Forms.Panel
$logTopPanel.Dock = 'Top'
$logTopPanel.Height = 36
$tabLog.Controls.Add($logTopPanel)

$logButtonRow = New-Object System.Windows.Forms.FlowLayoutPanel
$logButtonRow.Dock = 'Right'
$logButtonRow.FlowDirection = 'RightToLeft'
$logButtonRow.WrapContents = $false
$logButtonRow.AutoSize = $true
$logButtonRow.AutoSizeMode = 'GrowAndShrink'
$logButtonRow.Margin = New-Object System.Windows.Forms.Padding(0)
$logButtonRow.Padding = New-Object System.Windows.Forms.Padding(0, 4, 8, 0)
$logTopPanel.Controls.Add($logButtonRow)

$btnPopOutLog = New-Object System.Windows.Forms.Button
$btnPopOutLog.Text = 'Pop Out'
$btnPopOutLog.Size = New-Object System.Drawing.Size(90, 28)
$toolTip.SetToolTip($btnPopOutLog, 'Open a separate, resizable log window that stays live while you use the rest of the app.')
$logButtonRow.Controls.Add($btnPopOutLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Both'
$txtLog.WordWrap = $false
$txtLog.ReadOnly = $true
$txtLog.HideSelection = $false
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.Dock = 'Fill'
$tabLog.Controls.Add($txtLog)
$logTopPanel.BringToFront()

# Experimental scene controls. Scenes remain off by default, preserving the
# original single-source capture path byte-for-byte until explicitly enabled.
$chkSceneEnabled = New-Object System.Windows.Forms.CheckBox
$chkSceneEnabled.Text = 'Enable experimental scene composition'
$chkSceneEnabled.AutoSize = $true

$cmbScenePreset = New-Object System.Windows.Forms.ComboBox
$cmbScenePreset.DropDownStyle = 'DropDownList'
$null = $cmbScenePreset.Items.AddRange(@('Desktop + webcam', 'Desktop only', 'Webcam only'))
$cmbScenePreset.SelectedItem = 'Desktop + webcam'

$cmbSceneCompositor = New-Object System.Windows.Forms.ComboBox
$cmbSceneCompositor.DropDownStyle = 'DropDownList'
$null = $cmbSceneCompositor.Items.AddRange(@('D3D11 GPU (recommended)', 'CPU compatibility'))
$cmbSceneCompositor.SelectedIndex = 0

$cmbWebcamDevice = New-Object System.Windows.Forms.ComboBox
$cmbWebcamDevice.DropDownStyle = 'DropDownList'
$null = $cmbWebcamDevice.Items.Add('0: Default camera')
$cmbWebcamDevice.SelectedIndex = 0

$btnRefreshWebcams = New-Object System.Windows.Forms.Button
$btnRefreshWebcams.Text = 'Refresh cameras'

$btnRedrawScenePreview = New-Object System.Windows.Forms.Button
$btnRedrawScenePreview.Text = 'Redraw preview'
$toolTip.SetToolTip($btnRedrawScenePreview, 'Refreshes the embedded scene preview surface without restarting the GStreamer pipeline.')

$chkLiveSceneEditing = New-Object System.Windows.Forms.CheckBox
$chkLiveSceneEditing.Text = 'Edit scene while live (experimental)'
$chkLiveSceneEditing.AutoSize = $true
$chkLiveSceneEditing.Checked = $false
$toolTip.SetToolTip($chkLiveSceneEditing, 'Explicit opt-in. Available only with Dynamic previews. Runs compatible single-pipeline streams in a controlled worker process so placement, size, and opacity change on the actual broadcast without restarting. Stop/Restart terminates that worker exactly like the legacy launcher.')

$cmbWebcamLayout = New-Object System.Windows.Forms.ComboBox
$cmbWebcamLayout.DropDownStyle = 'DropDownList'
$null = $cmbWebcamLayout.Items.AddRange(@('Bottom right', 'Bottom left', 'Top right', 'Top left', 'Custom'))
$cmbWebcamLayout.SelectedItem = 'Bottom right'



$numWebcamWidth = New-SceneNumeric 64 3840 480 16
$numWebcamHeight = New-SceneNumeric 64 2160 270 16
$numWebcamX = New-SceneNumeric 0 7680 1420 10
$numWebcamY = New-SceneNumeric 0 4320 790 10
$numWebcamFps = New-SceneNumeric 1 240 30 1
$numWebcamOpacity = New-SceneNumeric 0 100 100 5
$numWebcamBorder = New-SceneNumeric 0 64 0 1

# Scene input queue controls. These replace the old hidden fixed scene queue
# values. 0 ms is honest: it emits max-size-time=0 and disables the time limit.
$numSceneInputQueueBuffers = New-SceneNumeric 1 64 $script:DefaultSceneInputQueueBuffers 1
$numSceneInputQueueCapMs = New-SceneNumeric 0 5000 $script:DefaultSceneInputQueueCapMs 5
$toolTip.SetToolTip($numSceneInputQueueBuffers, 'Queue depth applied independently to the desktop and webcam inputs immediately before the compositor.')
$toolTip.SetToolTip($numSceneInputQueueCapMs, 'Scene input queue time cap in milliseconds. 0 emits max-size-time=0; no hidden fallback is substituted.')

$chkWebcamMirror = New-Object System.Windows.Forms.CheckBox
$chkWebcamMirror.Text = 'Mirror webcam'
$chkWebcamMirror.AutoSize = $true

$chkWebcamAspectLock = New-Object System.Windows.Forms.CheckBox
$chkWebcamAspectLock.Text = 'Lock aspect ratio'
$chkWebcamAspectLock.AutoSize = $true
$chkWebcamAspectLock.Checked = $true
$toolTip.SetToolTip($chkWebcamAspectLock, 'Keeps webcam width and height coupled while resizing in the scene editor or changing geometry values.')

$lblSceneStatus = New-Object System.Windows.Forms.Label
$lblSceneStatus.Text = 'Scene composition is disabled; the existing capture pipeline is unchanged.'
$lblSceneStatus.AutoSize = $true

$txtScenePipeline = New-Object System.Windows.Forms.TextBox
$txtScenePipeline.Multiline = $true
$txtScenePipeline.ReadOnly = $true
$txtScenePipeline.ScrollBars = 'Both'
$txtScenePipeline.WordWrap = $false
$txtScenePipeline.Height = 110

# Visual scene editor. The canvas is a scaled representation of the encoded
# output; moving/resizing the webcam layer writes directly to the compositor
# X/Y/width/height controls used by Build-SceneCaptureChain.
$script:UpdatingSceneEditor = $false
$script:ScenePointerActive = $false
$script:ScenePointerMode = 'Move'
$script:ScenePointerStart = [System.Drawing.Point]::Empty
$script:SceneElementStartBounds = [System.Drawing.Rectangle]::Empty
$script:SceneSourceDragActive = $false
$script:WebcamAspectRatio = [double]$numWebcamWidth.Value / [double]$numWebcamHeight.Value

$sceneSourcePalette = New-Object System.Windows.Forms.FlowLayoutPanel
$sceneSourcePalette.Name = 'SceneSourcePalette'
$sceneSourcePalette.FlowDirection = 'LeftToRight'
$sceneSourcePalette.WrapContents = $false
$sceneSourcePalette.AutoSize = $false
$sceneSourcePalette.Height = 42
$sceneSourcePalette.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
$sceneSourcePalette.Padding = New-Object System.Windows.Forms.Padding(6)

$lblDesktopSource = New-Object System.Windows.Forms.Label
$lblDesktopSource.Text = '[box] Desktop (background)'
$lblDesktopSource.AutoSize = $false
$lblDesktopSource.Size = New-Object System.Drawing.Size(190, 28)
$lblDesktopSource.TextAlign = 'MiddleCenter'
$lblDesktopSource.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#1E293B')
$lblDesktopSource.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$sceneSourcePalette.Controls.Add($lblDesktopSource)

$lblWebcamSource = New-Object System.Windows.Forms.Label
$lblWebcamSource.Text = '[box] Webcam - drag to canvas'
$lblWebcamSource.AutoSize = $false
$lblWebcamSource.Size = New-Object System.Drawing.Size(210, 28)
$lblWebcamSource.TextAlign = 'MiddleCenter'
$lblWebcamSource.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17345C')
$lblWebcamSource.ForeColor = [System.Drawing.Color]::White
$lblWebcamSource.Cursor = [System.Windows.Forms.Cursors]::Hand
$sceneSourcePalette.Controls.Add($lblWebcamSource)

$sceneEditorCanvas = New-Object System.Windows.Forms.Panel
$sceneEditorCanvas.Name = 'SceneEditorCanvas'
$sceneEditorCanvas.Size = New-Object System.Drawing.Size(550, 309)
$sceneEditorCanvas.MinimumSize = New-Object System.Drawing.Size(420, 236)
$sceneEditorCanvas.BackColor = [System.Drawing.Color]::Black
$sceneEditorCanvas.BorderStyle = 'FixedSingle'
# Do not use WinForms AllowDrop/DoDragDrop here. Those APIs invoke OLE and throw
# when the PS2EXE/PowerShell host runs MTA. The editor uses control capture and
# screen-coordinate hit testing below, which works in both STA and MTA hosts.

$lblSceneDesktop = New-Object System.Windows.Forms.Label
$lblSceneDesktop.Dock = 'Fill'
$lblSceneDesktop.Text = "DESKTOP BACKGROUND`r`n1920 x 1080"
$lblSceneDesktop.TextAlign = 'MiddleCenter'
$lblSceneDesktop.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$lblSceneDesktop.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#050A12')
$sceneEditorCanvas.Controls.Add($lblSceneDesktop)

$sceneDesktopPreviewPanel = New-Object System.Windows.Forms.Panel
$sceneDesktopPreviewPanel.Name = 'SceneDesktopPreviewPanel'
$sceneDesktopPreviewPanel.Dock = 'Fill'
$sceneDesktopPreviewPanel.BackColor = [System.Drawing.Color]::Black
$sceneDesktopPreviewPanel.Visible = $false
$sceneEditorCanvas.Controls.Add($sceneDesktopPreviewPanel)

$sceneWebcamElement = New-Object System.Windows.Forms.Panel
$sceneWebcamElement.Name = 'SceneWebcamElement'
$sceneWebcamElement.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17345C')
$sceneWebcamElement.BorderStyle = 'FixedSingle'
$sceneWebcamElement.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$sceneEditorCanvas.Controls.Add($sceneWebcamElement)

$lblSceneWebcam = New-Object System.Windows.Forms.Label
$lblSceneWebcam.Dock = 'Top'
$lblSceneWebcam.Height = 24
$lblSceneWebcam.Text = 'WEBCAM - drag to move'
$lblSceneWebcam.TextAlign = 'MiddleCenter'
$lblSceneWebcam.ForeColor = [System.Drawing.Color]::White
$lblSceneWebcam.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17345C')
$lblSceneWebcam.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$sceneWebcamElement.Controls.Add($lblSceneWebcam)

$sceneWebcamPreviewPanel = New-Object System.Windows.Forms.Panel
$sceneWebcamPreviewPanel.Name = 'SceneWebcamPreviewPanel'
$sceneWebcamPreviewPanel.Dock = 'Fill'
$sceneWebcamPreviewPanel.BackColor = [System.Drawing.Color]::Black
$sceneWebcamPreviewPanel.Visible = $false
$sceneWebcamElement.Controls.Add($sceneWebcamPreviewPanel)

$sceneResizeHandle = New-Object System.Windows.Forms.Panel
$sceneResizeHandle.Name = 'SceneResizeHandle'
$sceneResizeHandle.Size = New-Object System.Drawing.Size(14, 14)
$sceneResizeHandle.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#60A5FA')
$sceneResizeHandle.Cursor = [System.Windows.Forms.Cursors]::SizeNWSE
$sceneWebcamElement.Controls.Add($sceneResizeHandle)

$lblSceneEditorHint = New-Object System.Windows.Forms.Label
$lblSceneEditorHint.Text = 'Drag Webcam from Sources onto the canvas. Drag the webcam header to move; drag its blue corner to resize.'
$lblSceneEditorHint.AutoSize = $true

























$scenePointerDown = {
    param($sender, $e)
    if (-not $script:SceneWorkspaceActive) { return }
    if (-not $chkSceneEnabled.Checked -or $e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $script:ScenePointerActive = $true
    $script:ScenePointerStart = [System.Windows.Forms.Cursor]::Position
    $script:SceneElementStartBounds = $sceneWebcamElement.Bounds
    $local = $sceneWebcamElement.PointToClient([System.Windows.Forms.Cursor]::Position)
    $script:ScenePointerMode = if ($local.X -ge ($sceneWebcamElement.Width - 18) -and $local.Y -ge ($sceneWebcamElement.Height - 18)) { 'Resize' } else { 'Move' }
    $sceneWebcamElement.Capture = $true
}

$scenePointerMove = {
    param($sender, $e)
    if (-not $script:ScenePointerActive) { return }
    $cursor = [System.Windows.Forms.Cursor]::Position
    $dx = $cursor.X - $script:ScenePointerStart.X
    $dy = $cursor.Y - $script:ScenePointerStart.Y
    $start = $script:SceneElementStartBounds
    if ($script:ScenePointerMode -eq 'Resize') {
        $maxWidth = [Math]::Max(24, $sceneEditorCanvas.ClientSize.Width - $start.Left)
        $maxHeight = [Math]::Max(18, $sceneEditorCanvas.ClientSize.Height - $start.Top)
        $newWidth = [Math]::Max(24, [Math]::Min($maxWidth, $start.Width + $dx))
        $newHeight = [Math]::Max(18, [Math]::Min($maxHeight, $start.Height + $dy))

        if ($chkWebcamAspectLock.Checked) {
            $displayAspect = if ($start.Height -gt 0) { [double]$start.Width / [double]$start.Height } else { $script:WebcamAspectRatio }
            if ($displayAspect -le 0) { $displayAspect = 16.0 / 9.0 }

            if ([Math]::Abs($dx) -ge [Math]::Abs($dy * $displayAspect)) {
                $newHeight = [Math]::Max(18, [int][Math]::Round($newWidth / $displayAspect))
            }
            else {
                $newWidth = [Math]::Max(24, [int][Math]::Round($newHeight * $displayAspect))
            }

            if ($newWidth -gt $maxWidth) {
                $newWidth = $maxWidth
                $newHeight = [Math]::Max(18, [int][Math]::Round($newWidth / $displayAspect))
            }
            if ($newHeight -gt $maxHeight) {
                $newHeight = $maxHeight
                $newWidth = [Math]::Max(24, [int][Math]::Round($newHeight * $displayAspect))
            }
        }

        $sceneWebcamElement.Size = New-Object System.Drawing.Size($newWidth, $newHeight)
        Update-SceneSelectionChrome
    }
    else {
        $newLeft = [Math]::Max(0, [Math]::Min($sceneEditorCanvas.ClientSize.Width - $start.Width, $start.Left + $dx))
        $newTop = [Math]::Max(0, [Math]::Min($sceneEditorCanvas.ClientSize.Height - $start.Height, $start.Top + $dy))
        $sceneWebcamElement.Location = New-Object System.Drawing.Point($newLeft, $newTop)
    }
    Push-ControlledSceneGeometryFromElement
}

$scenePointerUp = {
    param($sender, $e)
    if (-not $script:ScenePointerActive) { return }
    $script:ScenePointerActive = $false
    $sceneWebcamElement.Capture = $false
    Set-SceneValuesFromElement
    if (-not $chkWebcamAspectLock.Checked) { Capture-WebcamAspectRatio }
}

foreach ($dragControl in @($sceneWebcamElement, $lblSceneWebcam, $sceneResizeHandle)) {
    $dragControl.Add_MouseDown($scenePointerDown)
    $dragControl.Add_MouseMove($scenePointerMove)
    $dragControl.Add_MouseUp($scenePointerUp)
}



$lblWebcamSource.Add_MouseDown({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $script:SceneSourceDragActive = $true
    $lblWebcamSource.Capture = $true
    $lblWebcamSource.Text = '[box] Webcam - release on canvas'
})
$lblWebcamSource.Add_MouseMove({
    if (-not $script:SceneSourceDragActive) { return }
    $bounds = $sceneEditorCanvas.RectangleToScreen($sceneEditorCanvas.ClientRectangle)
    $lblWebcamSource.Cursor = if ($bounds.Contains([System.Windows.Forms.Cursor]::Position)) { [System.Windows.Forms.Cursors]::Cross } else { [System.Windows.Forms.Cursors]::Hand }
})
$lblWebcamSource.Add_MouseUp({
    param($sender, $e)
    if (-not $script:SceneSourceDragActive) { return }
    $script:SceneSourceDragActive = $false
    $lblWebcamSource.Capture = $false
    $lblWebcamSource.Text = '[box] Webcam - drag to canvas'
    $lblWebcamSource.Cursor = [System.Windows.Forms.Cursors]::Hand
    Place-WebcamOnSceneCanvas -ScreenPoint ([System.Windows.Forms.Cursor]::Position)
})
$sceneEditorCanvas.Add_SizeChanged({ Update-SceneCanvasFromValues })
$sceneDesktopPreviewPanel.Add_Resize({
    if (Get-Command Sync-DynamicScenePreviewLayout -ErrorAction SilentlyContinue) {
        Sync-DynamicScenePreviewLayout
    }
})
$sceneWebcamPreviewPanel.Add_Resize({
    if (Get-Command Sync-DynamicScenePreviewLayout -ErrorAction SilentlyContinue) {
        Sync-DynamicScenePreviewLayout
    }
})















$sceneResetUiRestartHandler = { Reset-DynamicScenePreviewFallback; Update-SceneUi; Restart-DynamicScenePreviewIfActive }
$sceneResetRestartHandler = { Reset-DynamicScenePreviewFallback; Restart-DynamicScenePreviewIfActive }
$btnRefreshWebcams.Add_Click({ Reset-DynamicScenePreviewFallback; Refresh-WebcamDevices; Update-SceneUi; Restart-DynamicScenePreviewIfActive })
$btnRedrawScenePreview.Add_Click({ Invoke-ScenePreviewRedraw })
$chkSceneEnabled.Add_CheckedChanged({ Reset-DynamicScenePreviewFallback; Update-SceneUi; Restart-DynamicScenePreviewIfActive; Sync-StandalonePreviewState -Quiet })
$chkLiveSceneEditing.Add_CheckedChanged({
    $script:SuppressControlledLiveStream = $false
    if ($script:LoadingSettings) {
        Update-SceneUi
        Update-CommandPreview
        return
    }

    $externalStreamRunning = (
        $script:GstProcess -and
        -not $script:GstProcess.HasExited -and
        -not $script:PreviewOnlyMode
    )
    if ($script:ControlledLiveStreamActive -or ($chkLiveSceneEditing.Checked -and $externalStreamRunning)) {
        $mode = if ($chkLiveSceneEditing.Checked) { 'controlled live editing' } else { 'the legacy launcher' }
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Live scene editing changed; restarting the stream with $mode."
        Stop-GstStream -Restart
    }
    Update-SceneUi
    Update-CommandPreview
})
$cmbScenePreset.Add_SelectedIndexChanged($sceneResetUiRestartHandler)
$cmbSceneCompositor.Add_SelectedIndexChanged($sceneResetUiRestartHandler)
$cmbWebcamDevice.Add_SelectedIndexChanged($sceneResetUiRestartHandler)
$cmbWebcamLayout.Add_SelectedIndexChanged({ Set-WebcamLayoutPreset; Update-SceneUi })
$numWebcamWidth.Add_ValueChanged({
    if ($script:UpdatingSceneEditor -or $script:LoadingSettings) { return }
    if ($chkWebcamAspectLock.Checked) {
        $script:UpdatingSceneEditor = $true
        try {
            $ratio = [Math]::Max(0.0001, $script:WebcamAspectRatio)
            $height = [Math]::Min([int]$numWebcamHeight.Maximum, [Math]::Max([int]$numWebcamHeight.Minimum, [int][Math]::Round([double]$numWebcamWidth.Value / $ratio)))
            $width = [Math]::Min([int]$numWebcamWidth.Maximum, [Math]::Max([int]$numWebcamWidth.Minimum, [int][Math]::Round($height * $ratio)))
            $numWebcamWidth.Value = [decimal]$width
            $numWebcamHeight.Value = [decimal]$height
        }
        finally { $script:UpdatingSceneEditor = $false }
    }
    else { Capture-WebcamAspectRatio }
    Update-SceneUi
})
$numWebcamHeight.Add_ValueChanged({
    if ($script:UpdatingSceneEditor -or $script:LoadingSettings) { return }
    if ($chkWebcamAspectLock.Checked) {
        $script:UpdatingSceneEditor = $true
        try {
            $ratio = [Math]::Max(0.0001, $script:WebcamAspectRatio)
            $width = [Math]::Min([int]$numWebcamWidth.Maximum, [Math]::Max([int]$numWebcamWidth.Minimum, [int][Math]::Round([double]$numWebcamHeight.Value * $ratio)))
            $height = [Math]::Min([int]$numWebcamHeight.Maximum, [Math]::Max([int]$numWebcamHeight.Minimum, [int][Math]::Round($width / $ratio)))
            $numWebcamWidth.Value = [decimal]$width
            $numWebcamHeight.Value = [decimal]$height
        }
        finally { $script:UpdatingSceneEditor = $false }
    }
    else { Capture-WebcamAspectRatio }
    Update-SceneUi
})
$chkWebcamAspectLock.Add_CheckedChanged({
    if ($chkWebcamAspectLock.Checked) { Capture-WebcamAspectRatio }
    Update-SceneUi
})
foreach ($control in @($numWebcamX,$numWebcamY,$numWebcamFps,$numWebcamOpacity,$numWebcamBorder,$numSceneInputQueueBuffers,$numSceneInputQueueCapMs)) { $control.Add_ValueChanged({ Update-SceneUi }) }
$numWebcamFps.Add_ValueChanged($sceneResetRestartHandler)
$numSceneInputQueueBuffers.Add_ValueChanged($sceneResetRestartHandler)
$numSceneInputQueueCapMs.Add_ValueChanged($sceneResetRestartHandler)
$numWidth.Add_ValueChanged({ Resize-LiveSceneCanvas; Resize-DynamicScenePreviewCardCanvas; Update-SceneCanvasFromValues })
$numHeight.Add_ValueChanged({ Resize-LiveSceneCanvas; Resize-DynamicScenePreviewCardCanvas; Update-SceneCanvasFromValues })
$chkWebcamMirror.Add_CheckedChanged($sceneResetUiRestartHandler)







Apply-ModernDashboardUi





















$chkStartMinimized.Add_CheckedChanged({
    Enforce-StartMinimizedTrayInvariant -Persist
})
$chkMinimizeToTray.Add_CheckedChanged({
    Enforce-StartMinimizedTrayInvariant -Persist
})


































































































































































































































































































































































































































































































































$previewHandler = { Update-CommandPreview }
$encoderUiHandler = { Update-EncoderUi }
$recordingUiHandler = { Update-RecordingUi }
$audioTimingPreviewHandler = { Update-AudioTimingOptionUi; Update-CommandPreview }

function Show-LogPopoutWindow {
    if ($script:LogPopoutForm -and -not $script:LogPopoutForm.IsDisposed) {
        if ($script:LogPopoutForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            $script:LogPopoutForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }
        $script:LogPopoutForm.Activate()
        return
    }

    $popout = New-Object System.Windows.Forms.Form
    $popout.Text = "$($script:AppName) - Log Console"
    $popout.StartPosition = 'Manual'
    $mainBounds = $form.Bounds
    $popout.Location = New-Object System.Drawing.Point(($mainBounds.Right + 12), $mainBounds.Top)
    $popout.Size = New-Object System.Drawing.Size(720, 600)
    $popout.MinimumSize = New-Object System.Drawing.Size(360, 240)
    $popout.BackColor = $script:ColorBg
    $popout.ForeColor = $script:ColorText
    $popout.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    if ($script:AppIcon) { $popout.Icon = $script:AppIcon }

    $popoutTextBox = New-Object System.Windows.Forms.TextBox
    $popoutTextBox.Multiline = $true
    $popoutTextBox.ScrollBars = 'Both'
    $popoutTextBox.WordWrap = $false
    $popoutTextBox.ReadOnly = $true
    $popoutTextBox.HideSelection = $false
    $popoutTextBox.Font = New-Object System.Drawing.Font('Consolas', 9)
    $popoutTextBox.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
    $popoutTextBox.ForeColor = $script:ColorText
    $popoutTextBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $popoutTextBox.Dock = 'Fill'
    $popoutTextBox.Text = $txtLog.Text
    $popout.Controls.Add($popoutTextBox)

    # Live-mirrored by Append-Log (13-ProcessLifecycle.ps1) for as long as this
    # form and textbox exist; clearing both references on close is what lets
    # Append-Log cheaply no-op once the window is gone instead of needing an
    # explicit "popout closed" notification path.
    $popout.Add_FormClosed({
        $script:LogPopoutForm = $null
        $script:LogPopoutTextBox = $null
    })

    $script:LogPopoutForm = $popout
    $script:LogPopoutTextBox = $popoutTextBox
    $popout.Show($form)
    Scroll-TextBoxToBottom -TextBox $popoutTextBox
}

function Show-CustomGstArgsEditor {
    $editor = New-Object System.Windows.Forms.Form
    $editor.Text = 'Custom gst-launch Arguments'
    $editor.StartPosition = 'CenterParent'
    $editor.Size = New-Object System.Drawing.Size(1000, 560)
    $editor.MinimumSize = New-Object System.Drawing.Size(560, 300)
    $editor.BackColor = $script:ColorBg
    $editor.ForeColor = $script:ColorText
    $editor.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $editor.ShowInTaskbar = $false
    if ($script:AppIcon) { $editor.Icon = $script:AppIcon }

    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Dock = 'Bottom'
    $buttonPanel.Height = 44
    $buttonPanel.BackColor = $script:ColorSurface
    $editor.Controls.Add($buttonPanel)

    $btnEditorCancel = New-Object System.Windows.Forms.Button
    $btnEditorCancel.Text = 'Cancel'
    $btnEditorCancel.Size = New-Object System.Drawing.Size(90, 28)
    $btnEditorCancel.Anchor = 'Top,Right'
    $btnEditorCancel.Location = New-Object System.Drawing.Point(($editor.ClientSize.Width - 98), 8)
    $btnEditorCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $buttonPanel.Controls.Add($btnEditorCancel)

    $btnEditorApply = New-Object System.Windows.Forms.Button
    $btnEditorApply.Text = 'Apply'
    $btnEditorApply.Size = New-Object System.Drawing.Size(90, 28)
    $btnEditorApply.Anchor = 'Top,Right'
    $btnEditorApply.Location = New-Object System.Drawing.Point(($editor.ClientSize.Width - 196), 8)
    $btnEditorApply.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $buttonPanel.Controls.Add($btnEditorApply)

    foreach ($editorButton in @($btnEditorApply, $btnEditorCancel)) {
        $editorButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $editorButton.FlatAppearance.BorderColor = $script:ColorBorder
        $editorButton.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#1F2937')
        $editorButton.ForeColor = $script:ColorText
        $editorButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    }

    $editorTextBox = New-Object System.Windows.Forms.TextBox
    $editorTextBox.Multiline = $true
    $editorTextBox.ScrollBars = 'Vertical'
    $editorTextBox.WordWrap = $true
    $editorTextBox.AcceptsReturn = $true
    $editorTextBox.AcceptsTab = $true
    $editorTextBox.HideSelection = $false
    $editorTextBox.Font = New-Object System.Drawing.Font('Consolas', 11)
    $editorTextBox.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
    $editorTextBox.ForeColor = $script:ColorText
    $editorTextBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $editorTextBox.Dock = 'Fill'
    $editorTextBox.Text = $txtCustomGstArguments.Text
    $editor.Controls.Add($editorTextBox)

    $editor.AcceptButton = $btnEditorApply
    $editor.CancelButton = $btnEditorCancel

    $result = $editor.ShowDialog($form)
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtCustomGstArguments.Text = $editorTextBox.Text
    }
    $editor.Dispose()
}

$chkCustomGstArgumentsEnabled.Add_CheckedChanged({
    if ($script:LoadingSettings) { return }
    Save-Settings
    Update-CommandPreview
})
$txtCustomGstArguments.Add_TextChanged({
    if ($script:LoadingSettings) { return }
    Save-Settings
    Update-CommandPreview
})
$btnUseGeneratedAsCustomGstArgs.Add_Click({
    $originalRecordingRequest = [bool]$script:RecordingPipelineRequested
    try {
        $pipelineRunning = $script:GstProcess -and -not $script:GstProcess.HasExited
        if (-not $pipelineRunning) {
            $script:RecordingPipelineRequested = [bool](
                $chkRecordingEnabled -and
                $chkRecordingEnabled.Checked -and
                $chkRecordWithStream -and
                $chkRecordWithStream.Checked -and
                ((-not $chkTransportEnabled) -or $chkTransportEnabled.Checked)
            )
        }

        $txtCustomGstArguments.Text = Build-GstArguments
        $chkCustomGstArgumentsEnabled.Checked = $true
        Save-Settings
        Update-CommandPreview
        $lowerTabs.SelectedTab = $tabCustomGstArgs
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not seed custom args from the generated command.`r`n`r`n$($_.Exception.Message)",
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
    }
    finally {
        $script:RecordingPipelineRequested = $originalRecordingRequest
    }
})
$btnClearCustomGstArgs.Add_Click({
    $txtCustomGstArguments.Clear()
    Save-Settings
    Update-CommandPreview
})
$btnPopOutCustomGstArgs.Add_Click({
    Show-CustomGstArgsEditor
})
$btnPopOutLog.Add_Click({
    Show-LogPopoutWindow
})



$txtGstPath.Add_TextChanged($previewHandler)
$txtDestination.Add_TextChanged({
    $protocol = [string]$cmbProtocol.SelectedItem
    if ($protocol -and -not $script:SuppressProtocolChange) {
        $script:ProtocolDestinations[$protocol] = $txtDestination.Text
    }
    Update-DirectWebRtcUi
    Update-CommandPreview
})
$cmbProtocol.Add_SelectedIndexChanged({
    Update-ProtocolUi
    Update-TimestampUi
    Update-CommandPreview
})
$chkTransportEnabled.Add_CheckedChanged({ Update-TransportUi })
$chkSendAbsoluteTimestamps.Add_CheckedChanged({ Update-TimestampUi; Update-CommandPreview })
$cmbTimingMode.Add_SelectedIndexChanged({
    Update-TransportUi
})
$chkSplitClockSignalingOverrides.Add_CheckedChanged({ Update-TimestampUi; Update-CommandPreview })
$cmbSplitVideoClockSignaling.Add_SelectedIndexChanged({ Update-TimestampUi; Update-CommandPreview })
$cmbSplitAudioClockSignaling.Add_SelectedIndexChanged({ Update-TimestampUi; Update-CommandPreview })
$cmbEncoder.Add_SelectedIndexChanged($encoderUiHandler)
$cmbAudioTransportMode.Add_SelectedIndexChanged({ Update-AudioCodecChoices; Update-CommandPreview })
$cmbSplitAudioPipelineClockMode.Add_SelectedIndexChanged($previewHandler)
$cmbAudioClockMode.Add_SelectedIndexChanged($previewHandler)
$cmbAudioTimingMode.Add_SelectedIndexChanged({ Update-AudioTimingOptionUi; Update-AudioCodecChoices; Update-CommandPreview })
$cmbAudioSlaveMethod.Add_SelectedIndexChanged($previewHandler)
$cmbAudioSyncMode.Add_SelectedIndexChanged($previewHandler)
$chkWasapiLowLatencyOverride.Add_CheckedChanged($audioTimingPreviewHandler)
$chkAudioBufferOverride.Add_CheckedChanged($audioTimingPreviewHandler)
$chkAudioLatencyOverride.Add_CheckedChanged($audioTimingPreviewHandler)
$chkAudioSampleRateOverride.Add_CheckedChanged($audioTimingPreviewHandler)



$numAudioBufferMs.Add_ValueChanged($previewHandler)
$numAudioLatencyMs.Add_ValueChanged($previewHandler)
$numAudioSampleRate.Add_ValueChanged($previewHandler)
$cmbDirectWebRtcOpusMode.Add_SelectedIndexChanged($previewHandler)
$cmbDirectWebRtcOpusFrameMs.Add_SelectedIndexChanged($previewHandler)
$cmbDirectWebRtcOpusAudioType.Add_SelectedIndexChanged($previewHandler)
$chkDirectWebRtcOpusFec.Add_CheckedChanged($previewHandler)
$chkDirectWebRtcOpusDtx.Add_CheckedChanged($previewHandler)

$cmbAudioCodec.Add_SelectedIndexChanged({
    if (-not $script:SuppressAudioCodecChange) {
        $protocol = [string]$cmbProtocol.SelectedItem
        $selected = [string]$cmbAudioCodec.SelectedItem
        if (
            -not [string]::IsNullOrWhiteSpace($protocol) -and
            -not [string]::IsNullOrWhiteSpace($selected) -and
            (Test-AudioCodecProtocolCompatibility `
                -AudioCodecName $selected `
                -Protocol $protocol)
        ) {
            $script:ProtocolAudioCodecs[$protocol] = $selected
        }
        Update-AudioCodecChoices -PreserveCurrent
    }
})
$numMonitor.Add_ValueChanged({ Update-CaptureModeUi; Update-CommandPreview })
$chkCursor.Add_CheckedChanged($previewHandler)
$cmbCaptureMethod.Add_SelectedIndexChanged({
    Sync-LegacyFullscreenFlag
    if (Test-FullscreenCaptureMode) {
        $null = Resolve-FullscreenCaptureTarget -Quiet
    }
    else {
        $script:CaptureWindowHwnd = [IntPtr]::Zero
        $script:CaptureWindowTitle = ''
        Update-CaptureModeUi
    }
    Update-CommandPreview
})
$chkFullscreenApp.Add_CheckedChanged({
    if ($chkFullscreenApp.Checked -and $cmbCaptureMethod.SelectedItem -ne 'Fullscreen App - D3D11 / WGC') {
        $cmbCaptureMethod.SelectedItem = 'Fullscreen App - D3D11 / WGC'
    }
    elseif (-not $chkFullscreenApp.Checked -and (Test-FullscreenCaptureMode)) {
        $cmbCaptureMethod.SelectedItem = $script:DefaultCaptureMethodName
    }
})
$chkPreview.Add_CheckedChanged({
    if ($script:LoadingSettings) {
        Update-CommandPreview
        return
    }

    if ($chkPreview.Checked) {
        Reset-DynamicScenePreviewFallback
    }

    if ($script:ControlledLiveStreamActive -and -not $chkPreview.Checked) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview disabled; restarting the live stream without controlled live scene editing."
        Stop-GstStream -Restart
        Update-CommandPreview
        return
    }

    if ($script:DynamicScenePreviewActive -and -not $chkPreview.Checked) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview disabled; stopping dynamic scene preview."
        Stop-DynamicScenePreview
        Update-CommandPreview
        return
    }

    if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
        if ($script:PreviewOnlyMode -and -not $chkPreview.Checked) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview disabled; stopping local preview."
            Stop-GstStream
        }
        elseif ($script:PipelineHasPreview) {
            Set-PreviewVisibility
            $previewState = if ($chkPreview.Checked) { 'shown' } else { 'hidden' }
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview $previewState without restarting stream."
        }
        elseif ($chkPreview.Checked -and $chkHidePreviewDuringStream.Checked -and (Test-TransportEnabled)) {
            $previewPlaceholder.Visible = $true
            $previewPlaceholder.Text = 'Preview hidden during stream'
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview remains hidden because Hide preview during stream is enabled."
        }
        elseif ($chkPreview.Checked) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview enabled; restarting stream to add preview pipeline branch."
            $lowerTabs.SelectedTab = $tabLog
            Stop-GstStream -Restart
        }
        else {
            $previewPlaceholder.Visible = $true
            $previewPlaceholder.Text = 'Preview disabled for this pipeline'
        }
    }
    else {
        if ($chkPreview.Checked) {
            $previewPlaceholder.Text = 'Starting local preview...'
            $lowerTabs.SelectedTab = $tabLog
            Sync-StandalonePreviewState
        }
        else {
            $previewPlaceholder.Text = 'Preview disabled for this pipeline'
        }
    }

    Update-CommandPreview
})
$chkHidePreviewDuringStream.Add_CheckedChanged({
    if ($script:LoadingSettings) {
        Update-CommandPreview
        return
    }

    if ($script:ControlledLiveStreamActive) {
        Sync-ControlledLivePreviewLayout
        $previewState = if ($chkHidePreviewDuringStream.Checked) { 'hidden throughout the UI; scene editing chrome remains available' } else { 'shown throughout the UI' }
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Controlled live preview $previewState without restarting the stream."
        Update-CommandPreview
        return
    }

    if ($script:GstProcess -and -not $script:GstProcess.HasExited -and -not $script:PreviewOnlyMode) {
        if ($script:PipelineHasPreview) {
            Set-PreviewVisibility
            $previewState = if ($chkHidePreviewDuringStream.Checked) { 'hidden during stream' } else { 'shown during stream' }
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview $previewState without restarting stream."
        }
        elseif ((-not $chkHidePreviewDuringStream.Checked) -and $chkPreview.Checked) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Hide preview during stream disabled; restarting stream to add preview pipeline branch."
            $lowerTabs.SelectedTab = $tabLog
            Stop-GstStream -Restart
        }
    }

    Update-CommandPreview
})
$chkAutoRestart.Add_CheckedChanged({
    if (-not $script:LoadingSettings -and -not $chkAutoRestart.Checked -and $script:AutomaticRestartPending) {
        $script:AutomaticRestartPending = $false
        $script:RestartAt = $null
        $script:RestartRecordingOnlyMode = $false
        $script:WaitingForFullscreen = $false
        Append-Log 'Pending automatic restart cancelled because Auto-restart on exit was disabled.'
        Set-RunState $false
    }
    Update-CommandPreview
})
$chkVerbose.Add_CheckedChanged($previewHandler)
$chkDiskProcessLogging.Add_CheckedChanged($previewHandler)
$chkPsDebug.Add_CheckedChanged($previewHandler)
$numWidth.Add_ValueChanged($previewHandler)
$numHeight.Add_ValueChanged($previewHandler)
$numFps.Add_ValueChanged($previewHandler)
$numVideoBitrate.Add_ValueChanged($previewHandler)
$cmbRateControl.Add_SelectedIndexChanged($encoderUiHandler)
$numMaxVideoBitrate.Add_ValueChanged($previewHandler)
$numDirectWebRtcMinBitrateKbps.Add_ValueChanged($previewHandler)
$numConstantQp.Add_ValueChanged($previewHandler)
$numGopSeconds.Add_ValueChanged($previewHandler)
$chkUnifiedBridgeKeyframeGuard.Add_CheckedChanged({ Update-UnifiedBridgeKeyframeUi; Update-CommandPreview })
$numUnifiedBridgeKeyframeIntervalMs.Add_ValueChanged($previewHandler)
$cmbPreset.Add_SelectedIndexChanged($previewHandler)
$cmbProfile.Add_SelectedIndexChanged($previewHandler)
$cmbEncoderTune.Add_SelectedIndexChanged($encoderUiHandler)
$cmbMultipass.Add_SelectedIndexChanged($previewHandler)
$cmbVideoPipelineClockMode.Add_SelectedIndexChanged($previewHandler)
$cmbVideoTimestampMode.Add_SelectedIndexChanged($previewHandler)
$cmbVideoSyncMode.Add_SelectedIndexChanged($previewHandler)
$numVbvBuffer.Add_ValueChanged($previewHandler)
$numBFrames.Add_ValueChanged($encoderUiHandler)
$chkLookAhead.Add_CheckedChanged($encoderUiHandler)
$numLookAheadFrames.Add_ValueChanged($encoderUiHandler)
$chkAdaptiveQuantization.Add_CheckedChanged($encoderUiHandler)
$chkTemporalAq.Add_CheckedChanged($encoderUiHandler)
$numAqStrength.Add_ValueChanged($encoderUiHandler)
$txtCustomEncoderOptions.Add_TextChanged($previewHandler)
$numSrtLatency.Add_ValueChanged($previewHandler)
$cmbRtspTransport.Add_SelectedIndexChanged($previewHandler)
$chkDesktopAudio.Add_CheckedChanged({
    Update-AudioCodecChoices -PreserveCurrent
})
$chkAudioMixerMode.Add_CheckedChanged($previewHandler)
$numDesktopVolume.Add_ValueChanged($previewHandler)
$chkMic.Add_CheckedChanged({
    Update-AudioCodecChoices -PreserveCurrent
})
$numMicVolume.Add_ValueChanged($previewHandler)
$cmbDesktopAudioDevice.Add_SelectedIndexChanged($previewHandler)
$cmbMicAudioDevice.Add_SelectedIndexChanged($previewHandler)
$btnRefreshAudioDevices.Add_Click({
    try {
        Refresh-AudioDevices
        Save-Settings
    }
    catch {
        Append-Log "Audio device refresh button failed: $($_.Exception.Message)"
        if ($lblAudioDeviceStatus) {
            $lblAudioDeviceStatus.Text = 'Audio device refresh failed; see log'
            $lblAudioDeviceStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
    }
})
$numAudioBitrate.Add_ValueChanged($previewHandler)
$chkStartMediaMtx.Add_CheckedChanged({
    Update-MediaMtxUi
    Update-CommandPreview
})
$chkUpnpEnabled.Add_CheckedChanged({
    if ($script:ActiveUpnpMappings.Count -eq 0) {
        $lblUpnpStatus.Text = if ($chkUpnpEnabled.Checked) { 'UPnP: enabled - will map ports when the stream starts' } else { 'UPnP: disabled' }
        $lblUpnpStatus.ForeColor = [System.Drawing.Color]::DimGray
    }
})
$chkDdnsEnabled.Add_CheckedChanged({
    Update-DdnsUi
    if (-not $script:DdnsLastAppliedIp) {
        $lblDdnsStatus.Text = if ($chkDdnsEnabled.Checked) { 'DDNS: enabled - will update when the stream starts' } else { 'DDNS: disabled' }
        $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DimGray
    }
})
$cmbDdnsProvider.Add_SelectedIndexChanged({ Update-DdnsUi; Update-LetsEncryptUi })
$btnDdnsUpdateNow.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    try { Update-DdnsRecord } catch { Append-Log "DDNS: $($_.Exception.Message)" }
    Save-Settings
})
$chkLetsEncryptEnabled.Add_CheckedChanged({ Update-LetsEncryptUi })
$chkViewerAuthenticationEnabled.Add_CheckedChanged({ Update-ViewerAuthenticationUi; Update-PlayerConfigFromUi })
$btnViewerAuthenticationAddAccount.Add_Click({ Add-ViewerAuthenticationAccount })
$btnViewerAuthenticationRemoveAccount.Add_Click({ Remove-ViewerAuthenticationAccount })
$btnViewerAuthenticationEnableTotp.Add_Click({ Enable-ViewerAuthenticationTotp })
$btnViewerAuthenticationDisableTotp.Add_Click({ Disable-ViewerAuthenticationTotp })
$btnLetsEncryptIssueNow.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    try { Update-LetsEncryptCertificate } catch { Append-Log "ACME: $($_.Exception.Message)" }
    Save-Settings
})
# Live-typing convenience for Cloudflare: auto-fill Zone from everything
# after Hostname's first dot, but only until the user types into Zone
# directly (or Load-Settings finds a saved Zone already on disk -- see
# 24-Settings.ps1), at which point their value always wins.
$txtDdnsHostname.Add_TextChanged({
    if ($script:LoadingSettings -or $script:DdnsCloudflareZoneManuallySet) { return }
    $dotIndex = $txtDdnsHostname.Text.IndexOf('.')
    if ($dotIndex -lt 0) { return }
    $derivedZone = $txtDdnsHostname.Text.Substring($dotIndex + 1)
    if ($txtDdnsCloudflareZoneId.Text -ne $derivedZone) {
        $script:DdnsSuppressZoneAutoFill = $true
        $txtDdnsCloudflareZoneId.Text = $derivedZone
        $script:DdnsSuppressZoneAutoFill = $false
    }
})
$txtDdnsCloudflareZoneId.Add_TextChanged({
    if ($script:LoadingSettings -or $script:DdnsSuppressZoneAutoFill) { return }
    $script:DdnsCloudflareZoneManuallySet = -not [string]::IsNullOrWhiteSpace($txtDdnsCloudflareZoneId.Text)
})

foreach ($control in @(
    $txtDirectWebRtcSignalingHost,
    $numDirectWebRtcSignalingPort,
    $numDirectWebRtcSplitAudioSignalingPort,
    $chkDirectWebRtcSharedSignaling,
    $chkSplitClockSignalingOverrides,
    $cmbSplitVideoClockSignaling,
    $cmbSplitAudioClockSignaling,
    $cmbDirectWebRtcMediaStreamGrouping,
    $txtDirectWebRtcVideoMediaStreamId,
    $txtDirectWebRtcAudioMediaStreamId,
    $chkDirectWebRtcUnifiedPublisher,
    $numDirectWebRtcBridgeVideoPort,
    $numDirectWebRtcBridgeAudioPort,
    $numDirectWebRtcBridgeJitterMs,
    $numDirectWebRtcPublisherQueueMs,
    $chkDirectWebRtcAudioBridgePacing,
    $chkDirectWebRtcControlDataChannel,
    $cmbDirectWebRtcBundlePolicy,
    $numDirectWebRtcInternalRtpMtu,
    $chkDirectWebRtcInternalRepeatHeaders,
    $txtDirectWebRtcStun,
    $chkDirectWebRtcTurnEnabled,
    $txtDirectWebRtcTurn,
    $numDirectWebRtcMinRtpPort,
    $numDirectWebRtcMaxRtpPort,
    $chkUpnpEnabled,
    $chkUpnpMapSignaling,
    $numUpnpSignalingExternalPort,
    $numUpnpSplitAudioExternalPort,
    $chkUpnpMapRtp,
    $chkUpnpMapWebServer,
    $numUpnpWebServerExternalPort,
    $txtDirectWebRtcWebPath,
    $txtPlayerVideoSignalingProxyPath,
    $txtPlayerAudioSignalingProxyPath,
    $chkViewerAuthenticationEnabled,
    $cmbDirectWebRtcBundledWebMode,
    $txtDirectWebRtcBundledWebDirectory,
    $cmbDirectWebRtcWorkingWebMode,
    $txtDirectWebRtcWebDirectory,
    $cmbDirectWebRtcCongestion,
    $numDirectWebRtcStartBitrateKbps,
    $numDirectWebRtcMinBitrateKbps,
    $cmbDirectWebRtcMitigation,
    $cmbWebRtcRecoveryMode,
    $cmbWebRtcSenderQueueMode,
    $cmbThreadingProfile,
    $cmbGstProcessPriority,
    $cmbQueueLeakMode,
    $chkDirectWebRtcFec,
    $chkDirectWebRtcRetransmission,
    $cmbJbufWatchdogMode,
    $numJbufMaxMs,
    $numDirectWebRtcPlayerJitterMs,
    $numDirectWebRtcVideoJitterMs,
    $chkPlayerStatsOverlay,
    $chkPlayerJbufDebug,
    $numLiveEdgeAverageSec,
    $numLiveEdgeGreenMs,
    $numLiveEdgeYellowMs,
    $chkPlayerUrlOverrides,
    $cmbDirectWebRtcOpusMode,
    $cmbDirectWebRtcOpusFrameMs,
    $cmbDirectWebRtcOpusAudioType,
    $chkDirectWebRtcOpusFec,
    $chkDirectWebRtcOpusDtx
)) {
    if ($control -is [System.Windows.Forms.TextBox]) {
        $control.Add_TextChanged({ Update-PlayerConfigFromUi })
    }
    elseif ($control -is [System.Windows.Forms.NumericUpDown]) {
        $control.Add_ValueChanged({ Update-PlayerConfigFromUi })
    }
    elseif ($control -is [System.Windows.Forms.ComboBox]) {
        $control.Add_SelectedIndexChanged({ Update-PlayerConfigFromUi })
    }
    elseif ($control -is [System.Windows.Forms.CheckBox]) {
        $control.Add_CheckedChanged({ Update-PlayerConfigFromUi })
    }
}

$btnBrowseDirectWebRtcBundledWebDirectory.Add_Click({
    try {
        $initial = $txtDirectWebRtcBundledWebDirectory.Text
        if ([string]::IsNullOrWhiteSpace($initial)) { $initial = Get-BundledDirectWebRtcWebDirectory }
        $picked = Select-DirectWebRtcFolderPath -Title 'Select bundled/static gstwebrtc-api\dist source folder' -InitialPath $initial -AllowNewFolder:$false
        if ([string]::IsNullOrWhiteSpace($picked)) { return }
        $txtDirectWebRtcBundledWebDirectory.Text = $picked
        $cmbDirectWebRtcBundledWebMode.SelectedItem = 'Manual path'
        if (Test-DirectWebRtcWebDirectory $picked) {
            Append-Log "Bundled Web UI source selected: $picked"
        }
        else {
            Append-Log "Bundled Web UI source selected, but index.html/player.js were not found: $picked"
            [System.Windows.Forms.MessageBox]::Show('Selected bundled source must contain index.html and player.js.', $script:AppName, 'OK', 'Warning') | Out-Null
        }
        Save-Settings
        Update-PlayerConfigFromUi
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not select bundled Web UI source: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$btnDetectDirectWebRtcBundledWebDirectory.Add_Click({
    try {
        $found = ''
        if (-not [string]::IsNullOrWhiteSpace($script:ApplicationDirectory)) {
            $candidate = Join-Path $script:ApplicationDirectory 'gstwebrtc-api\dist'
            if (Test-DirectWebRtcWebDirectory $candidate) { $found = [System.IO.Path]::GetFullPath($candidate) }
        }
        if ([string]::IsNullOrWhiteSpace($found)) { $found = Find-DirectWebRtcWebDirectory $txtGstPath.Text }
        if ([string]::IsNullOrWhiteSpace($found)) {
            Append-Log 'Bundled Web UI source was not found. Need gstwebrtc-api\dist beside the app/script or select it manually.'
            [System.Windows.Forms.MessageBox]::Show('Could not find bundled gstwebrtc-api\dist automatically. Select the bundled source folder manually.', $script:AppName, 'OK', 'Warning') | Out-Null
        }
        else {
            $txtDirectWebRtcBundledWebDirectory.Text = $found
            $cmbDirectWebRtcBundledWebMode.SelectedItem = 'Manual path'
            Append-Log "Bundled Web UI source detected: $found"
        }
        Save-Settings
        Update-PlayerConfigFromUi
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not detect bundled Web UI source: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$btnBrowseDirectWebRtcWebDirectory.Add_Click({
    try {
        $initial = $txtDirectWebRtcWebDirectory.Text
        if ([string]::IsNullOrWhiteSpace($initial)) { $initial = Get-DefaultDirectWebRtcWorkingWebDirectory }
        $picked = Select-DirectWebRtcFolderPath -Title 'Select writable working/served Web UI directory' -InitialPath $initial -AllowNewFolder:$true
        if ([string]::IsNullOrWhiteSpace($picked)) { return }
        $txtDirectWebRtcWebDirectory.Text = $picked
        $cmbDirectWebRtcWorkingWebMode.SelectedItem = 'Manual path'
        if (-not (Test-DirectWebRtcWebDirectoryWritable $picked)) {
            Append-Log "Working Web UI directory selected, but it is not writable: $picked"
            [System.Windows.Forms.MessageBox]::Show('Selected working Web UI directory is not writable.', $script:AppName, 'OK', 'Warning') | Out-Null
            return
        }
        Save-Settings
        $source = Get-DirectWebRtcSourceWebDirectory
        $served = Ensure-DirectWebRtcRuntimeWebDirectory $source
        Write-DirectWebRtcWebClientConfig
        Append-Log "Working Web UI directory selected: $picked; serving from $served"
        Update-DirectWebRtcUi
        Update-CommandPreview
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not select working Web UI directory: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$btnDetectDirectWebRtcWebDirectory.Add_Click({
    try {
        $working = Get-DefaultDirectWebRtcWorkingWebDirectory
        $txtDirectWebRtcWebDirectory.Text = $working
        $cmbDirectWebRtcWorkingWebMode.SelectedItem = 'Auto: LocalAppData'
        if (-not (Test-DirectWebRtcWebDirectoryWritable $working)) { throw "Working directory is not writable: $working" }
        $source = Get-DirectWebRtcSourceWebDirectory
        $served = Ensure-DirectWebRtcRuntimeWebDirectory $source
        Write-DirectWebRtcWebClientConfig
        Save-Settings
        Append-Log "Working Web UI directory detected/created: $served"
        Update-DirectWebRtcUi
        Update-CommandPreview
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not detect/create working Web UI directory: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})


$btnRefreshDirectWebRtcWebUi.Add_Click({
    try {
        $source = Get-DirectWebRtcSourceWebDirectory
        $served = Ensure-DirectWebRtcRuntimeWebDirectory -SourceDirectory $source -ForceRefresh
        Write-DirectWebRtcWebClientConfig
        Update-DirectWebRtcWebUiStatus
        Append-Log "Direct WebRTC web UI force refresh requested from Player tab: $source -> $served"
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not refresh Direct WebRTC web UI: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$btnOpenDirectWebRtcServedDir.Add_Click({
    try {
        $served = Get-DirectWebRtcWorkingWebDirectory
        if (-not (Test-Path -LiteralPath $served)) { $null = New-Item -ItemType Directory -Path $served -Force }
        Start-Process explorer.exe $served | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not open working/served web UI directory: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$btnOpenDirectWebRtcBundledDir.Add_Click({
    try {
        $bundled = Get-BundledDirectWebRtcWebDirectory
        if ([string]::IsNullOrWhiteSpace($bundled)) { throw 'Bundled gstwebrtc-api\dist directory not found beside the app/script.' }
        Start-Process explorer.exe $bundled | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not open bundled web UI directory: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$btnOpenDirectWebRtcViewer.Add_Click({
    try {
        Start-Process (Get-DirectWebRtcViewerUrl) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not open viewer URL: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$cmbDirectWebRtcSmoothnessProfile.Add_SelectedIndexChanged({
    Apply-DirectWebRtcSmoothnessProfile
    Update-DirectWebRtcUi
    Update-CommandPreview
})

foreach ($smoothControl in @($numDirectWebRtcPacingMs, $numDirectWebRtcPlayerJitterMs, $numDirectWebRtcVideoJitterMs, $numJbufMaxMs)) {
    $smoothControl.Add_ValueChanged({
        if (-not $script:ApplyingDirectWebRtcSmoothnessProfile -and $cmbDirectWebRtcSmoothnessProfile.SelectedItem -ne 'Custom') { $cmbDirectWebRtcSmoothnessProfile.SelectedItem = 'Custom' }
        Update-PlayerConfigFromUi
    })
}

foreach ($splitPlayerNumeric in @($numSplitAudioStallSeconds, $numSplitAudioWarmupSeconds, $numSplitAvOffsetBaselineMs, $numSplitAvOffsetWarnMs)) {
    $splitPlayerNumeric.Add_ValueChanged({ Update-PlayerConfigFromUi })
}

$numLiveEdgeGreenMs.Add_ValueChanged({
    if ($numLiveEdgeYellowMs.Value -le $numLiveEdgeGreenMs.Value) {
        $numLiveEdgeYellowMs.Value = [decimal]([Math]::Min([int]$numLiveEdgeYellowMs.Maximum, [int]$numLiveEdgeGreenMs.Value + 1))
    }
})
$numLiveEdgeYellowMs.Add_ValueChanged({
    if ($numLiveEdgeYellowMs.Value -le $numLiveEdgeGreenMs.Value) {
        $numLiveEdgeGreenMs.Value = [decimal]([Math]::Max([int]$numLiveEdgeGreenMs.Minimum, [int]$numLiveEdgeYellowMs.Value - 1))
    }
})

foreach ($playerControl in @($chkPlayerStatsOverlay, $chkPlayerJbufDebug, $chkPlayerUrlOverrides, $chkPlayerSeparateHtmlMediaElements, $cmbDirectWebRtcAvPipelineMode, $cmbSplitPlayerSyncMode, $cmbJbufWatchdogMode)) {
    if ($playerControl -is [System.Windows.Forms.CheckBox]) {
        $playerControl.Add_CheckedChanged({ Update-PlayerConfigFromUi })
    }
    elseif ($playerControl -is [System.Windows.Forms.ComboBox]) {
        $playerControl.Add_SelectedIndexChanged({ Update-PlayerConfigFromUi })
    }
}

$cmbThreadingProfile.Add_SelectedIndexChanged({ Apply-ThreadingProfile; Save-Settings })
$cmbThreadBudget.Add_SelectedIndexChanged({ Apply-ThreadBudget; Save-Settings })
foreach ($budgetControl in @($numCpuWorkerLimit,$chkBudgetCaptureQueue,$chkBudgetSenderQueue,$chkBudgetAudioInputQueue,$chkBudgetAudioFinalQueue)) {
    if ($budgetControl -is [System.Windows.Forms.NumericUpDown]) {
        $budgetControl.Add_ValueChanged({
            if ($script:ApplyingThreadBudget) { return }
            if ($cmbThreadBudget.SelectedItem -ne 'Custom') { $cmbThreadBudget.SelectedItem = 'Custom' }
            Update-CommandPreview
            Save-Settings
        })
    }
    else {
        $budgetControl.Add_CheckedChanged({
            if ($script:ApplyingThreadBudget) { return }
            if ($cmbThreadBudget.SelectedItem -ne 'Custom') { $cmbThreadBudget.SelectedItem = 'Custom' }
            Update-CommandPreview
            Save-Settings
        })
    }
}
foreach ($threadingControl in @($cmbGstProcessPriority, $cmbQueueLeakMode, $numCaptureQueueBuffers, $numAudioQueueBuffers, $numAudioQueueCapMs, $chkBufferLatenessTracer)) {
    if ($threadingControl -is [System.Windows.Forms.ComboBox]) {
        $threadingControl.Add_SelectedIndexChanged({
            if (-not $script:ApplyingThreadingProfile -and $cmbThreadingProfile.SelectedItem -ne 'Custom') { $cmbThreadingProfile.SelectedItem = 'Custom' }
            Update-CommandPreview
        })
    }
    elseif ($threadingControl -is [System.Windows.Forms.NumericUpDown]) {
        $threadingControl.Add_ValueChanged({
            if (-not $script:ApplyingThreadingProfile -and $cmbThreadingProfile.SelectedItem -ne 'Custom') { $cmbThreadingProfile.SelectedItem = 'Custom' }
            Update-CommandPreview
        })
    }
    elseif ($threadingControl -is [System.Windows.Forms.CheckBox]) {
        $threadingControl.Add_CheckedChanged({
            if (-not $script:ApplyingThreadingProfile -and $cmbThreadingProfile.SelectedItem -ne 'Custom') { $cmbThreadingProfile.SelectedItem = 'Custom' }
            Update-CommandPreview
        })
    }
}

$cmbGstDebugMode.Add_SelectedIndexChanged({ Update-GstDebugUi; Save-Settings; Update-CommandPreview })
$txtGstDebugSpec.Add_TextChanged({ Save-Settings; Update-CommandPreview })
$chkGstDebugNoColor.Add_CheckedChanged({ Save-Settings; Update-CommandPreview })

foreach ($smoothCombo in @($cmbWebRtcRecoveryMode, $cmbWebRtcSenderQueueMode)) {
    $smoothCombo.Add_SelectedIndexChanged({
        if (-not $script:ApplyingDirectWebRtcSmoothnessProfile -and $cmbDirectWebRtcSmoothnessProfile.SelectedItem -ne 'Custom') { $cmbDirectWebRtcSmoothnessProfile.SelectedItem = 'Custom' }
        if ($cmbWebRtcRecoveryMode.SelectedItem) { Set-WebRtcRecoveryMode ([string]$cmbWebRtcRecoveryMode.SelectedItem) }
        Update-DirectWebRtcUi
        Update-CommandPreview
    })
}

$btnResetWebRtcSane.Add_Click({ Reset-WebRtcSaneDefaults; Save-Settings; Append-Log 'WebRTC/receiver knobs and Video sender queue reset to sane defaults.' })

$btnCopyDirectWebRtcViewer.Add_Click({
    try {
        [System.Windows.Forms.Clipboard]::SetText((Get-DirectWebRtcViewerUrl))
        Append-Log "Direct WebRTC viewer URL copied: $(Get-DirectWebRtcViewerUrl)"
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not copy viewer URL: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$chkRecordingEnabled.Add_CheckedChanged({
    if (-not $script:LoadingSettings -and -not $chkRecordingEnabled.Checked -and $script:RecordingPipelineActive) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Recording disabled; removing the active recording branch."
        if ($script:RecordingOnlyMode) { Stop-GstStream } else { Stop-GstStream -Restart }
    }
    Update-RecordingUi
})
$chkRecordWithStream.Add_CheckedChanged({
    if (-not $script:LoadingSettings) { Save-Settings }
    Update-RecordingUi
})
$btnToggleRecording.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Invoke-ToggleRecording
})
$txtRecordingDirectory.Add_TextChanged($previewHandler)
$txtRecordingTemplate.Add_TextChanged($previewHandler)
$cmbRecordingEncoder.Add_SelectedIndexChanged($recordingUiHandler)
$cmbRecordingPreset.Add_SelectedIndexChanged($previewHandler)
$cmbRecordingProfile.Add_SelectedIndexChanged($previewHandler)
$numRecordingWidth.Add_ValueChanged($previewHandler)
$numRecordingHeight.Add_ValueChanged($previewHandler)
$numRecordingFps.Add_ValueChanged($previewHandler)
$numRecordingVideoBitrate.Add_ValueChanged($previewHandler)
$cmbRecordingRateControl.Add_SelectedIndexChanged($recordingUiHandler)
$numRecordingMaxVideoBitrate.Add_ValueChanged($previewHandler)
$numRecordingConstantQp.Add_ValueChanged($previewHandler)
$numRecordingGopSeconds.Add_ValueChanged($previewHandler)
$numRecordingBFrames.Add_ValueChanged($recordingUiHandler)
$cmbRecordingTune.Add_SelectedIndexChanged($recordingUiHandler)
$cmbRecordingMultipass.Add_SelectedIndexChanged($previewHandler)
$chkRecordingLookAhead.Add_CheckedChanged($recordingUiHandler)
$numRecordingLookAheadFrames.Add_ValueChanged($previewHandler)
$chkRecordingSpatialAq.Add_CheckedChanged($recordingUiHandler)
$chkRecordingTemporalAq.Add_CheckedChanged($recordingUiHandler)
$numRecordingAqStrength.Add_ValueChanged($previewHandler)
$numRecordingVbvBuffer.Add_ValueChanged($previewHandler)
$txtRecordingCustomEncoderOptions.Add_TextChanged($previewHandler)
$chkRecordingDesktopAudio.Add_CheckedChanged($recordingUiHandler)
$chkRecordingMic.Add_CheckedChanged($recordingUiHandler)
$numRecordingAudioBitrate.Add_ValueChanged($previewHandler)

$resetDefaultsBindings = @(
    @{ Button = $btnResetTransport; ResetFunction = 'Reset-TransportDefaults' }
    @{ Button = $btnResetVideo;     ResetFunction = 'Reset-VideoDefaults' }
    @{ Button = $btnResetAudio;     ResetFunction = 'Reset-AudioDefaults' }
    @{ Button = $btnResetRecording; ResetFunction = 'Reset-RecordingDefaults' }
    @{ Button = $btnResetNetwork;   ResetFunction = 'Reset-DdnsDefaults' }
    @{ Button = $btnResetOptions;   ResetFunction = 'Reset-OptionsDefaults' }
)
foreach ($binding in $resetDefaultsBindings) {
    $resetFunction = $binding.ResetFunction
    $binding.Button.Add_Click({ & $resetFunction; Save-Settings }.GetNewClosure())
}
$btnExportLabConfig.Add_Click({ Export-LabConfiguration })
$cmbProfilePreset.Add_SelectedIndexChanged({ Update-ProfileSelectionUi })
$btnLoadProfile.Add_Click({ Invoke-LoadSelectedProfile })
$btnSaveProfile.Add_Click({ Save-CurrentProfile })
$btnSaveProfileAs.Add_Click({ Save-ProfileAs })
$btnDeleteProfile.Add_Click({ Remove-SelectedProfile })
$btnExportProfile.Add_Click({ Export-SelectedProfile })
$btnImportProfile.Add_Click({ Import-ProfileFile })
$btnResetAll.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show(
        'Reset all GStreamer Glass app settings to defaults? This will not restore or delete Windows network snapshots.',
        $script:AppName,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) { Reset-AllAppDefaults }
})

$previewPanel.Add_Resize({
    if ($script:SceneEditorCanvasHostedInPreview) {
        Resize-DynamicScenePreviewCardCanvas
    }
    elseif ($script:PreviewHwnd -ne [IntPtr]::Zero) {
        Set-PreviewVisibility
    }
})

$btnBrowseGst.Add_Click({
    try {
        $selectedPath = [GstExecutableBrowser]::SelectGstLaunch($txtGstPath.Text)
        if (-not [string]::IsNullOrWhiteSpace($selectedPath)) {
            $txtGstPath.Text = $selectedPath
            Append-Log "Selected GStreamer executable: $selectedPath"
            if (Test-GstLaunchPath $selectedPath) {
                Prepare-GStreamerRuntime -GstPath $selectedPath
            }
        }
    }
    catch {
        $message = "Could not open the GStreamer executable browser.`r`n`r`n$($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            $message,
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        Append-Log "Executable browser error: $($_.Exception.ToString())"
    }
})

$btnBrowseMediaMtx.Add_Click({
    try {
        $selectedPath =
            [GstExecutableBrowser]::SelectMediaMtx($txtMediaMtxPath.Text)

        if (-not [string]::IsNullOrWhiteSpace($selectedPath)) {
            $txtMediaMtxPath.Text = $selectedPath
            Append-Log "Selected MediaMTX executable: $selectedPath"
        }
    }
    catch {
        $message =
            "Could not open the MediaMTX executable browser.`r`n`r`n" +
            $_.Exception.Message

        [System.Windows.Forms.MessageBox]::Show(
            $message,
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null

        Append-Log "MediaMTX browser error: $($_.Exception.ToString())"
    }
})

$btnBrowseRecordingDirectory.Add_Click({
    try {
        $selectedPath = [GstExecutableBrowser]::SelectFolder(
            $txtRecordingDirectory.Text,
            'Select GStreamer Glass recording folder'
        )

        if (-not [string]::IsNullOrWhiteSpace($selectedPath)) {
            $txtRecordingDirectory.Text = $selectedPath
            Append-Log "Selected recording folder: $selectedPath"
        }
    }
    catch {
        $message =
            "Could not open the recording folder browser.`r`n`r`n" +
            $_.Exception.Message

        [System.Windows.Forms.MessageBox]::Show(
            $message,
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null

        Append-Log "Recording folder browser error: $($_.Exception.ToString())"
    }
})

$btnDetectGst.Add_Click({
    $detected = Find-GstLaunch
    $txtGstPath.Text = $detected
    Append-Log "Detected GStreamer executable: $detected"
    if (Test-GstLaunchPath $detected) {
        Prepare-GStreamerRuntime -GstPath $detected
    }
})
$btnCheckGst.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Test-GStreamerElements
})

$btnStart.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Invoke-StreamToggle
})

$btnStop.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Request-StreamStop
})

$btnRestart.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Stop-GstStream -Restart -ViewerRestart
})
$btnCopyCommand.Add_Click({
    try {
        [System.Windows.Forms.Clipboard]::SetText($txtCommand.Text)
        $lowerTabs.SelectedTab = $tabCommand
        $statusLabel.Text = 'Command copied'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkBlue
    }
    catch {
        Append-Log "Clipboard error: $($_.Exception.Message)"
    }
})
$btnClearLog.Add_Click({ $txtLog.Clear() })

$btnOpenLogs.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $script:LogDirectory)) {
            if (-not (Test-ProcessDiskLoggingEnabled)) {
                Append-Log 'No process log folder exists. Disk process logging is disabled.'
                $lowerTabs.SelectedTab = $tabLog
                return
            }

            Ensure-ProcessLogDirectory
        }

        Start-Process `
            -FilePath 'explorer.exe' `
            -ArgumentList @($script:LogDirectory) |
            Out-Null
    }
    catch {
        Append-Log "Could not open log folder: $($_.Exception.Message)"
        $lowerTabs.SelectedTab = $tabLog
    }
})

$notifyIcon.Add_MouseDoubleClick({
    param($sender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Show-MainWindow
    }
})
$trayMenu.Add_Opening({ Update-TrayMenuState })
$trayShowItem.Add_Click({ Show-MainWindow })
$trayStartItem.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Start-GstStream
})

$trayStopItem.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Request-StreamStop
})

$trayRestartItem.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Stop-GstStream -Restart -ViewerRestart
})
$trayExitItem.Add_Click({
    try {
        $form.ShowInTaskbar = $true
        $form.Show()
    }
    catch {}
    $form.Close()
})

$form.Add_Resize({
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $script:DynamicPreviewUiReady = $false
    }

    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized -and $script:PreviewOnlyMode) {
        Sync-StandalonePreviewState
    }

    if (
        $chkMinimizeToTray.Checked -and
        $form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized
    ) {
        if ($script:StartupTrayHidePending) {
            Hide-MainWindowToTray -SuppressBalloon
            $script:StartupTrayHidePending = $false
        }
        else {
            Hide-MainWindowToTray
        }
    }
    elseif ($form.Visible -and $script:GstProcess -and -not $script:GstProcess.HasExited) {
        Set-PreviewVisibility
    }
    elseif (
        $form.Visible -and
        $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized -and
        -not ($script:GstProcess -and -not $script:GstProcess.HasExited)
    ) {
        $null = $form.BeginInvoke([Action]{
            try {
                if (
                    $form.Visible -and
                    $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized -and
                    -not $script:StartupTrayHidePending -and
                    -not $script:TrayRestoreInProgress
                ) {
                    $script:DynamicPreviewUiReady = $true
                }
                Sync-StandalonePreviewState -Quiet
            }
            catch {}
        })
    }

    if ($script:SceneWorkspaceActive) {
        Invoke-ScenePreviewRedraw -Quiet
    }
})

$form.Add_VisibleChanged({
    if ($form.Visible -and $script:GstProcess -and -not $script:GstProcess.HasExited) {
        $null = $form.BeginInvoke([Action]{
            try {
                if ($script:PreviewParked) {
                    Restore-PreviewWindowFromParking
                }
                Try-AttachPreview
                Set-PreviewVisibility
            }
            catch {}
        })
    }
    elseif ($form.Visible -and -not ($script:GstProcess -and -not $script:GstProcess.HasExited)) {
        $null = $form.BeginInvoke([Action]{
            try {
                if (
                    $form.Visible -and
                    $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized -and
                    -not $script:StartupTrayHidePending -and
                    -not $script:TrayRestoreInProgress
                ) {
                    $script:DynamicPreviewUiReady = $true
                }
                Sync-StandalonePreviewState -Quiet
            }
            catch {}
        })
    }
    elseif (-not $form.Visible -and $script:PreviewOnlyMode) {
        Sync-StandalonePreviewState
    }
    elseif (-not $form.Visible -and $script:PreviewHwnd -ne [IntPtr]::Zero) {
        Park-PreviewWindow
    }
})

$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 400
$pollTimer.Add_Tick({
    # Drain all four log streams, then append once. Four separate Append-Log calls
    # meant four AppendText + trim-check + forced-scroll passes per tick on the UI
    # thread; batching collapses that to one.
    $pending = Drain-ManagedProcessLogs
    if ($pending) { Append-Log $pending }
    Update-GstThreadCountStatus
    Drain-LetsEncryptTlsProxyLogs

    Try-AttachPreview

    if ($script:DynamicScenePreviewActive) {
        $controlledTerminal = $null
        try { $controlledTerminal = [GstControlledScenePreview]::PollTerminalMessage() }
        catch { $controlledTerminal = "bus polling failed: $($_.Exception.Message)" }

        if ($controlledTerminal) {
            Append-Log "Controlled scene compositor terminal message: $controlledTerminal"
            Invoke-DynamicScenePreviewFallback -Reason 'reported a terminal pipeline error'
            return
        }
        if (-not [GstControlledScenePreview]::IsRunning) {
            Invoke-DynamicScenePreviewFallback -Reason 'stopped unexpectedly'
            return
        }
    }

    if (
        $script:MediaMtxProcess -and
        $script:MediaMtxProcess.HasExited
    ) {
        $mediaExitCode = $script:MediaMtxProcess.ExitCode
        Append-Log (
            "[$(Get-Date -Format 'HH:mm:ss')] Managed MediaMTX exited " +
            "unexpectedly with code $mediaExitCode."
        )

        try { $script:MediaMtxProcess.Dispose() } catch {}
        $script:MediaMtxProcess = $null
        $script:MediaMtxPathInUse = ''

        if (($script:GstProcess -and -not $script:GstProcess.HasExited) -or $script:ControlledLiveStreamActive) {
            Append-Log (
                'Stopping the stream because its managed MediaMTX server is no ' +
                'longer running.'
            )

            if ($chkAutoRestart.Checked) {
                Stop-GstStream -Restart -AutomaticRestart
            }
            else {
                Stop-GstStream -SuppressPreviewRestore
            }
        }
        else {
            Remove-ActiveProcessState

            # Nothing left running to produce MediaMTX output. Drain the tail, then
            # stop tracking so we do not reopen dead log files on every tick.
            $mediaFinalText = Drain-ManagedProcessLogs
            if ($mediaFinalText) { Append-Log $mediaFinalText }
            $script:MediaMtxStdOutPath = $null
            $script:MediaMtxStdErrPath = $null
            $script:MediaMtxStdOutPosition = [int64]0
            $script:MediaMtxStdErrPosition = [int64]0
        }
    }

    if ((Test-FullscreenCaptureMode) -and $script:GstProcess -and -not $script:GstProcess.HasExited -and (Get-Date) -ge $script:NextFullscreenProbe) {
        $script:NextFullscreenProbe = (Get-Date).AddSeconds(1)

        if ($script:CaptureWindowHwnd -ne [IntPtr]::Zero -and -not [GstPreviewNative]::WindowExists($script:CaptureWindowHwnd)) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Fullscreen application closed; stopping the pipeline."
            $script:CaptureWindowHwnd = [IntPtr]::Zero
            $script:CaptureWindowTitle = ''
            Update-CaptureModeUi
            if ($chkAutoRestart.Checked) {
                Stop-GstStream -Restart -AutomaticRestart
            }
            else {
                Append-Log 'Auto-restart is disabled; fullscreen capture will remain stopped.'
                Stop-GstStream -SuppressPreviewRestore
            }
        }
        else {
            $captureGstPid = if ((Test-DirectWebRtcUnifiedPublisher) -and $script:GstVideoProcess -and -not $script:GstVideoProcess.HasExited) { $script:GstVideoProcess.Id } else { $script:GstProcess.Id }
            $candidate = [GstPreviewNative]::FindTopmostFullscreenWindow($PID, $captureGstPid)
            if ($candidate -ne [IntPtr]::Zero -and $candidate -ne $script:CaptureWindowHwnd) {
                $newTitle = [GstPreviewNative]::GetWindowTitleSafe($candidate)
                Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Fullscreen application changed to '$newTitle'; rebuilding the pipeline."
                $script:CaptureWindowHwnd = $candidate
                $script:CaptureWindowTitle = $newTitle
                Update-CaptureModeUi
                if ($chkAutoRestart.Checked) {
                    Stop-GstStream -Restart -AutomaticRestart
                }
                else {
                    Append-Log 'Auto-restart is disabled; the fullscreen target change will not rebuild the pipeline.'
                    Stop-GstStream -SuppressPreviewRestore
                }
            }
        }
    }

    if ($script:GstVideoProcess -and $script:GstVideoProcess.HasExited -and $script:GstProcess -and -not $script:GstProcess.HasExited) {
        $videoExitCode = $script:GstVideoProcess.ExitCode
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Split video bridge exited unexpectedly with code $videoExitCode; stopping the complete topology."
        try { $script:GstVideoProcess.Dispose() } catch {}
        $script:GstVideoProcess = $null
        if ($chkAutoRestart.Checked) { Stop-GstStream -Restart -AutomaticRestart } else { Stop-GstStream -SuppressPreviewRestore }
        return
    }

    if ($script:GstAudioProcess -and $script:GstAudioProcess.HasExited -and $script:GstProcess -and -not $script:GstProcess.HasExited) {
        $audioExitCode = $script:GstAudioProcess.ExitCode
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Split audio pipeline exited unexpectedly with code $audioExitCode; stopping the complete topology."
        try { $script:GstAudioProcess.Dispose() } catch {}
        $script:GstAudioProcess = $null
        if ($chkAutoRestart.Checked) { Stop-GstStream -Restart -AutomaticRestart } else { Stop-GstStream -SuppressPreviewRestore }
        return
    }

    if ($script:GstProcess -and $script:GstProcess.HasExited) {
        $exitCode = $script:GstProcess.ExitCode
        $wasRequested = $script:StopRequested
        $wasPreviewOnly = [bool]$script:PreviewOnlyMode
        $wasRecordingOnly = [bool]$script:RecordingOnlyMode
        $wasControlledLive = [bool]$script:ControlledLiveStreamActive

        if ($wasControlledLive) {
            Close-ControlledLiveWorkerPipe
            $script:ControlledLiveStreamActive = $false
            $script:ControlledLivePreviewSurfaceHwnd = [IntPtr]::Zero
            $script:ControlledLivePreviewAppliedSize = [System.Drawing.Size]::Empty
        }
        Close-WebRtcPortRangeWorkerPipe

        if ($script:GstVideoProcess -and -not $script:GstVideoProcess.HasExited) { try { Stop-ProcessTreeById -ProcessId $script:GstVideoProcess.Id } catch {} }
        if ($script:GstAudioProcess -and -not $script:GstAudioProcess.HasExited) { try { Stop-ProcessTreeById -ProcessId $script:GstAudioProcess.Id } catch {} }
        try { if ($script:GstVideoProcess) { $script:GstVideoProcess.Dispose() } } catch {}
        try { if ($script:GstAudioProcess) { $script:GstAudioProcess.Dispose() } } catch {}
        $script:GstVideoProcess = $null
        $script:GstAudioProcess = $null

        try { $script:GstProcess.Dispose() } catch {}
        $script:GstProcess = $null
        Stop-ManagedMediaMtx -Quiet
        Remove-ActiveProcessState

        # Final drain, then stop tracking these logs. The paths were previously left
        # populated after exit, so every subsequent tick reopened and re-seeked four
        # dead files forever at 2.5 Hz.
        $finalText = Drain-ManagedProcessLogs
        if ($finalText) { Append-Log $finalText }
        $script:StdOutPath = $null
        $script:StdErrPath = $null
        $script:StdOutVideoPath = $null
        $script:StdErrVideoPath = $null
        $script:StdOutPosition = [int64]0
        $script:StdErrPosition = [int64]0
        $script:StdOutVideoPosition = [int64]0
        $script:StdErrVideoPosition = [int64]0
        $script:MediaMtxStdOutPath = $null
        $script:MediaMtxStdErrPath = $null
        $script:MediaMtxStdOutPosition = [int64]0
        $script:MediaMtxStdErrPosition = [int64]0

        $script:PreviewHwnd = [IntPtr]::Zero
        $script:PreviewOnlyMode = $false
        $script:ForceLocalPreviewMode = $false
        $script:RecordingPipelineRequested = $false
        $script:RecordingPipelineActive = $false
        $script:RecordingOnlyMode = $false
        Reset-PreviewAppliedState
        $previewPlaceholder.Visible = $true
        $previewPlaceholder.Text = if ($wasPreviewOnly -and -not $wasRequested) { 'Preview failed' } else { 'Preview stopped' }
        Set-RunState $false

        if ($wasRequested) {
            $statusLabel.Text = 'Stopped'
            $statusLabel.ForeColor = [System.Drawing.Color]::Black
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Pipeline stopped."
            $null = $form.BeginInvoke([Action]{
                try { Sync-StandalonePreviewState -Quiet } catch {}
            })
        }
        elseif ($wasPreviewOnly) {
            $script:RestartAt = $null
            $statusLabel.Text = "Preview exited - code $exitCode"
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
            $lowerTabs.SelectedTab = $tabLog
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Standalone preview exited unexpectedly with code $exitCode; no stream restart will be scheduled for a preview-only failure."
        }
        else {
            $statusLabel.Text = "Pipeline exited - code $exitCode"
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
            $lowerTabs.SelectedTab = $tabLog
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Pipeline exited unexpectedly with code $exitCode."

            if ($wasControlledLive) {
                $script:SuppressControlledLiveStream = $true
                if ($chkAutoRestart.Checked) {
                    $script:AutomaticRestartPending = $true
                    $script:RestartAt = (Get-Date).AddMilliseconds(800)
                    Append-Log 'Controlled live worker failure latched; automatic restart will use the legacy external launcher.'
                    Set-RunState $false
                }
                else {
                    $script:AutomaticRestartPending = $false
                    $script:RestartAt = $null
                    Append-Log 'Controlled live worker failure latched; Auto-restart is disabled, so the pipeline will remain stopped.'
                }
            }
            elseif ($chkAutoRestart.Checked) {
                $script:AutomaticRestartPending = $true
                $script:RestartRecordingOnlyMode = $wasRecordingOnly
                $script:RestartAt = (Get-Date).AddSeconds(2)
                if (Test-FullscreenCaptureMode) {
                    $script:WaitingForFullscreen = $true
                    Set-WaitingForFullscreenState
                    Append-Log 'Fullscreen capture will retry every 2 seconds until an application is available.'
                }
                else {
                    Append-Log 'Automatic full restart scheduled in 2 seconds.'
                }
                Set-RunState $false
            }
            else {
                $script:AutomaticRestartPending = $false
                $script:RestartAt = $null
                Append-Log 'Auto-restart is disabled; no pipeline restart will be attempted.'
            }
        }

        $script:StopRequested = $false
    }

    if (-not $script:GstProcess -and $script:RestartAt -and (Get-Date) -ge $script:RestartAt) {
        $script:RestartAt = $null
        $restartWasAutomatic = [bool]$script:AutomaticRestartPending
        $script:AutomaticRestartPending = $false
        $restartRecordingOnly = [bool]$script:RestartRecordingOnlyMode
        $script:RestartRecordingOnlyMode = $false
        if ($restartWasAutomatic -and -not $chkAutoRestart.Checked) {
            Append-Log 'Pending automatic restart cancelled because Auto-restart on exit is disabled.'
            $script:WaitingForFullscreen = $false
            Set-RunState $false
            return
        }
        if ($restartRecordingOnly) {
            Start-GstStream -Automatic -RecordingOnly
        }
        else {
            Start-GstStream -Automatic
        }
    }
})
$pollTimer.Start()

$form.Add_Shown({
    Refresh-WebcamDevices
    Load-Settings
    Write-PsDebugTrace "GStreamer Glass v$($script:AppVersion) started."
    # Repair legacy configs that contain StartMinimized=true alongside
    # MinimizeToTray=false, then write the corrected invariant immediately.
    Enforce-StartMinimizedTrayInvariant -Persist
    Update-GstDebugUi
    Initialize-GstJob
    Stop-StaleManagedProcesses
    if (Test-FullscreenCaptureMode) {
        $null = Resolve-FullscreenCaptureTarget -Quiet
    }
    Update-CaptureModeUi
    Update-TransportUi
    Update-AudioCodecChoices
    Update-AudioTimingOptionUi
    Update-EncoderUi
    Update-RecordingUi
    Update-DdnsUi
    Update-LetsEncryptUi
    Update-SceneUi
    Refresh-ProfileList
    Update-CommandPreview
    Update-TrayMenuState
    Append-Log "Application icon: $($script:AppIconSource)"

    if ($chkStartMinimized.Checked) {
        # Do not let dynamic preview processes touch hidden/zero-sized controls
        # during startup. Show-MainWindow enables them after a real restore.
        $script:DynamicPreviewUiReady = $false
        $null = $form.BeginInvoke([Action]{
            Apply-StartMinimized
        })
    }
    elseif ($script:StartupTrayHidePending) {
        $script:StartupTrayHidePending = $false
        $script:DynamicPreviewUiReady = $true
        try {
            $form.Opacity = 1
            $form.ShowInTaskbar = $true
        }
        catch {}
    }
    else {
        $script:DynamicPreviewUiReady = $true
        Sync-StandalonePreviewState -Quiet
    }
})



$form.Add_FormClosing({
    Save-Settings
    $pollTimer.Stop()
    Invoke-ApplicationCleanup
})

# Prepare the initial minimized-to-tray window state before Application.Run()
# makes the form visible. Previously settings were loaded only from the Shown
# event, so Start minimized could briefly paint the main window before hiding it.
# This small pre-read only affects first-paint visibility; Load-Settings still
# remains the full source of truth during Shown.
try {
    $startupStartMinimized = [bool]$chkStartMinimized.Checked

    if (Test-Path -LiteralPath $script:ConfigPath) {
        $startupSettings =
            Get-Content -LiteralPath $script:ConfigPath -Raw |
            ConvertFrom-Json

        if ($null -ne $startupSettings.StartMinimized) {
            $startupStartMinimized = [bool]$startupSettings.StartMinimized
        }
    }

    # Start minimized always means start in tray. Do not consult the legacy
    # MinimizeToTray value here: the historical true/false mismatch let Resize
    # hide the form before Shown finished initializing controls and previews.
    if ($startupStartMinimized) {
        $script:StartupTrayHidePending = $true
        $form.ShowInTaskbar = $false
        $form.Opacity = 0
    }
}
catch {
    # Startup pre-hide is cosmetic only. If it fails, fall back to normal startup.
    try {
        $script:StartupTrayHidePending = $false
        $form.Opacity = 1
        $form.ShowInTaskbar = $true
    }
    catch {}
}

try {
    # ApplicationContext owns the tray-capable message loop. Hiding MainForm
    # leaves the loop alive, while closing MainForm exits it exactly once. Do
    # not call ExitThread from FormClosed: that can recursively re-enter the
    # WinForms shutdown path and terminate with StackOverflowException.
    $applicationContext = New-Object System.Windows.Forms.ApplicationContext
    $applicationContext.MainForm = $form
    [System.Windows.Forms.Application]::Run($applicationContext)
}
finally {
    Invoke-ApplicationCleanup
}
