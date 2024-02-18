---
title: My Sony A7 IV settings
author: Petr Ruzicka
date: 2022-09-02
description: My Photo and Video Sony A7 IV settings
categories: [Photography, Cameras]
tags: [Sony A7 IV, settings, video, photo, cameras]
mermaid: true
image: /assets/img/posts/2022/2022-09-02-my-sony-a7-iv-settings/Sony_A7_IV_(ILCE-7M4)_-_by_Henry_Soderlund_(51739988735).avif
---

I wanted to summarize my notes about the Sony A7 IV settings.

Settings are separate into Photo and Video section to have them separated.

## Photo

```mermaid
flowchart LR
    AA1[My Menu \n Setting] --> AA2(Add Item)                --> AA3(Drive Mode)                  --> AA4(Interval \n Shoot Func.)
    AB1[My Menu \n Setting] --> AB2(Add Item)                --> AB3(Drive Mode)                  --> AB4(Bracket \n Settings)
    AC1[My Menu \n Setting] --> AC2(Add Item)                --> AC3(Finder / Monitor)            --> AC4(Monitor \n Brightness)
    AD1[My Menu \n Setting] --> AD2(Add Item)                --> AD3(Zebra Display)               --> AD4(Zebra Display)
    AE1[My Menu \n Setting] --> AE2(Add Item)                --> AE3(Zebra Display)               --> AE4(Bluetooth)                --> AE5(Bluetooth \n Function)
    AF1[My Menu \n Setting] --> AF2(Add Item)                --> AF3(Finder Monitor)              --> AF4(Select \n Finder/Monitor)
    AG1[Shooting]           --> AG2(Image Quality)           --> AG3(JPEG/HEIF Switch)            --> AG4("HEIF (4:2:0)")
    AH1[Shooting]           --> AH2(Image Quality)           --> AH3(Image Quality \n Settings)   --> AH4(Slot 1)                   --> AH5(File Format)                        --> AH6(RAW)
    AI1[Shooting]           --> AI2(Image Quality)           --> AI3(Image Quality \n Settings)   --> AI4(Slot 1)                   --> AI5(RAW \n File Type)                   --> AI6(Losseless \n Comp)
    AJ1[Shooting]           --> AJ2(Image Quality)           --> AJ3(Lens \n Compensation)        --> AJ4(Distortion Comp.)         --> AJ5(Auto)
    AK1[Shooting]           --> AK2(Media)                   --> AK3(Rec. Media \n Settings)      --> AK4(Auto Switch Media)
    AL1[Shooting]           --> AL2(File)                    --> AL3(File/Folder \n Settings)     --> AL4(Set File Name)            --> AL5("A74")
    AM1[Shooting]           --> AM2(File)                    --> AM3(Copyright Info)              --> AM4(Write Copyright \n Info)  --> AM5(On)
    AN1[Shooting]           --> AN2(File)                    --> AN3(Copyright Info)              --> AN4(Set Photographer)         --> AN5("My Name")
    AO1[Shooting]           --> AO2(File)                    --> AO3(Copyright Info)              --> AO4(Set Copyright)            --> AO5("CC BY-SA")
    AP1[Shooting]           --> AP2(File)                    --> AP3(Write \n Serial Number)      --> AP4(On)
    AQ1[Shooting]           --> AQ2(Drive Mode)              --> AQ3(Drive Mode)                  --> AQ4(Cont. Shooting:)          --> AQ5(Mid)
    AR1[Shooting]           --> AR2(Drive Mode)              --> AR3(Bracket Settings)            --> AR4("Selftimer")              --> AR5(2 sec)
    AS1[Shooting]           --> AS2(Drive Mode)              --> AS3(Interval Shoot \n Func.)     --> AS4(Shooting \n start time)   --> AS5(2 sec)
    AT1[Shooting]           --> AT2(Drive Mode)              --> AT3(Interval Shoot \n Func.)     --> AT4(Shooting interval)        --> AT5(5 sec)
    AU1[Shooting]           --> AU2(Drive Mode)              --> AU3(Interval Shoot \n Func.)     --> AU4(Shooting interval)        --> AU5(Number of shots)                    --> AU6(300)
    AV1[Shooting]           --> AV2(Drive Mode)              --> AV3(Interval Shoot \n Func.)     --> AV4(Shooting interval)        --> AV5(AE Tracking \n Sensitivity)         --> AV6(Low)
    AW1[Exposure/Color]     --> AW2(Exposure)                --> AW3(ISO Range Limit)             --> AW4(50)                       --> AW5(12800)
    AX1[Exposure/Color]     --> AX2(Metering)                --> AX3(Spot Metering Point)         --> AX4(Focus Point Link)
    AY1[Exposure/Color]     --> AY2(Zebra Display)           --> AY3(Zebra Display)               --> AY4(On)
    AZ1[Exposure/Color]     --> AZ2(Zebra Display)           --> AZ3(Zebra Level)                 --> AZ4(C1)                       --> AZ5(Lower Limit)                        --> AZ6(109+)
    BA1[Focus]              --> BA2(AF/MF)                   --> BA3(Focus Mode)                  --> BA4(Continuous AF)
    BB1[Focus]              --> BB2(AF/MF)                   --> BB3(AF Illuminator)              --> BB4(Off)
    BC1[Focus]              --> BC2(Focus Area)              --> BC3(Tracking:)                   --> BC4(Spot S)
    BD1[Focus]              --> BD2(Focus Area)              --> BD3(Focus Area Color)            --> BD4(Red)
    BE1[Focus]              --> BE2(Face/Eye AF)             --> BE3(Face/Eye Frame Disp.)        --> BE4(On)
    BF1[Focus]              --> BF2(Peaking \n Display)      --> BF3(On)
    BG1[Focus]              --> BG2(Peaking \n Display)      --> BG3(Peaking Color)               --> BG4(Red)
    BH1[Playback]           --> BH2(Magnification)           --> BH3(Enlarge Initial \n Position) --> BH4(Focused Position)
    BI1[Playback]           --> BI2(Delete)                  --> BI3(Delete pressing \n twice)    --> BI4(On)
    BJ1[Playback]           --> BJ2(Playback \n Option)      --> BJ3(Focus \n Frame Display)      --> BJ4(On)
    BK1[Network]            --> BK2(Smartphone \n Connect)   --> BK3(Smartphone Regist.)
    BL1[Network]            --> BL2(Smartphone \n Connect)   --> BL3(Remote \n Shoot Setting)     --> BL4(Still Img. \n Save Dest.) --> BL5(Camera Only)
    BM1[Network]            --> BM2(Transfer \n Remote)      --> BM3(FTP Transfer \n Func.)       --> BM4(FTP Function)             --> BM5(On)
    BN1[Network]            --> BN2(Transfer \n Remote)      --> BN3(FTP Transfer \n Func.)       --> BN4(Server \n Setting)        --> BN5(Server 1)                           --> BN6(...)
    BO1[Network]            --> BO2(Transfer \n Remote)      --> BO3(FTP Transfer \n Func.)       --> BO4(FTP Transfer)             --> BO5(Target Group)                       --> BO6(This Media)
    BP1[Network]            --> BP2(Transfer \n Remote)      --> BP3(FTP Transfer \n Func.)       --> BP4(FTP Power \n Save)        --> BP5(On)
    BQ1[Network]            --> BQ2(Wi-Fi)                   --> BQ3(Wi-Fi Frequency \n Band)     --> BQ4(2.4 GHz)
    BR1[Network]            --> BR2(Wi-Fi)                   --> BR3(Access Point \n Set.)        --> BR4(2.4 GHz)
    BS1[Setup]              --> BS2(Operations \n Customize) --> BS3(Custom Key/Dial \n Set.)     --> BS4(Rear1)                    --> BS5(4)                                  --> BS6(Shutter/Silent) --> BS7(Switch \n Silent Mode)
    BT1[Setup]              --> BT2(Operations \n Customize) --> BT3(Custom Key/Dial \n Set.)     --> BT4(Rear1)                    --> BT5(2)                                  --> BT6(Image Quality)  --> BT7(APS-C S35 \n Full Frame)
    BU1[Setup]              --> BU2(Operations \n Customize) --> BU3(Custom Key/Dial \n Set.)     --> BU4(Dial/Wheel)               --> BU5(4)                                  --> BU6(Exposure)       --> BU7(ISO)
    BV1[Setup]              --> BV2(Operations \n Customize) --> BV3(Custom Key/Dial \n Set.)     --> BV4(Dial/Wheel)               --> BV5(Separate M mode \n and other modes)
    BX1[Setup]              --> BX2(Operations \n Customize) --> BX3(Fn Menu Settings)            --> BX4(Face/Eye AF)              --> BX5(Face/Eye \n Subject)
    BY1[Setup]              --> BY2(Operations \n Customize) --> BY3(Fn Menu Settings)            --> BY4(Exposure)                 --> BY5(ISO AUTO Min. SS)
    BZ1[Setup]              --> BZ2(Operations \n Customize) --> BZ3(Fn Menu Settings)            --> BZ4(Zebra Display)            --> BZ5(Zebra Display)
    CA1[Setup]              --> CA2(Operations \n Customize) --> CA3(Fn Menu Settings)            --> CA4(White Balance)            --> CA5(White Balance)
    CB1[Setup]              --> CB2(Operations \n Customize) --> CB3("DISP (Screen Disp) \n Set") --> CB4(Finder)                   --> CB5(Display All \n Info.)
    CC1[Setup]              --> CC2(Touch \n Operation)      --> CC3(Touch Operation)             --> CC4(On)
    CD1[Setup]              --> CD2(Touch \n Operation)      --> CD3(Touch Panel/Pad)             --> CD4(Touch Pad Only)
    CE1[Setup]              --> CE2(Touch \n Operation)      --> CE3(Touch Func. \n in Shooting)  --> CE4(Touch Focus)
    CF1[Setup]              --> CF2(Touch \n Operation)      --> CF3(Touch Pad Settings)          --> CF4(Operation Area)           --> CF5(Left 1/2)
    CG1[Setup]              --> CG2(Display \n Option)       --> CG3(Auto Review)                 --> CG4(2s)
    CH1[Setup]              --> CH2(Power Setting \n Option) --> CH3(Auto Power OFF \n Temp.)     --> CH4(High)
    CI1[Setup]              --> CI2(Sound Option)            --> CI3(Audio signals)               --> CI4(Off)
    CJ1[Setup]              --> CJ2(Setup Option)            --> CJ3(Anti-dust Function)          --> CJ4(Shutter When \n Pwr OFF)  --> CJ5(On)
    CK1[Setup]              --> CK2(USB)                     --> CK3(USB Connection \n Mode)      --> CK4("MassStorage(MSC)")
```

## Video

```mermaid
flowchart LR
    A1[Shooting]         --> A2(Image Quality)           --> A3(File Format)                   --> A4(XAVC HS 4K)
    B1[Shooting]         --> B2(Image Quality)           --> B3(Movie Settings)                --> B4(Record Setting)         --> B5(140M 4:2:2 10bit)
    C1[Shooting]         --> C2(Image Quality)           --> C3(S&Q Settings)                  --> C4(Frame Rate)             --> C5(1fps)
    D1[Shooting]         --> D2(File)                    --> D3(File Name Format)              --> D4(Date + Title)
    E1[Shooting]         --> E2(File)                    --> E3(File Name Format)              --> E4(Title Name \n Settings) --> E5(A74_)
    F1[Exposure / Color] --> F2(Color / Tone)            --> F3(Picture Profile)               --> F4(PP11)
    G1[Setup]            --> G2(Operations \n Customize) --> G3(Different Set \n for Still/Mv) --> G4("(Select all)")
    H1[Setup]            --> H2(Operations \n Customize) --> H3(REC w/ Shutter)                --> H4(On)
```

Links:

- [Sony A7IV BEGINNER'S GUIDE to Custom Settings - Part 1](https://youtu.be/-HhGqIgPh5w)
- [Top 7 Settings to Change on Sony a7 IV](https://youtu.be/NtKcMXIPMK8)
- [Sony A7IV – Best Settings For Photography](https://youtu.be/lXQy1xWNyJM)
- [Sony A7 IV Beginners Guide - Set-Up, Menus, & How-To Use the Camera](https://youtu.be/Vt3g42Y56jI)
