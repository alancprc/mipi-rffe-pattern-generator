# setup file

## number of device.

should be successive and start from 1.

```
DUT: 1, 2
```

## clock/data pin
the name for clock pin for each device.

```
ClockPinName: CLK_pin, CLK2_pin
```

the name for data pin for each device.
```
DataPinName: DATA_pin, DATA2_pin
```

## trigger pin
the name for trigger pin. leave blank if no trigger pin needed.
```
TriggerPinName: FX_TRIGGER_pin
```

## extra pin
the name for extra pins, separated by ',' for multiple pin.
leave blank if no extra pins needed.
the format is: <pin name>=<default logic state>
e.g.: 'vramp=1' will add pin "vramp" to uno pattern, with logic state '1';
```
ExtraPinName: VRAMP_pin=0
```

## register table
the csv file name for each device.
```
RegisterTable: regtable_dut1.csv, regtable_dut1.csv
```

## waveform reference
the waveform reference for read/write cycle
```
WaveformRefRead: TS13MHz
WaveformRefWrite: TS26MHz
```

## supported directive:
```
    directive        -   micro instruction in Unison Pattern
     wait N          -   <RPT N>
     trig            -   <TRIG>
     jmp label_name  -   <JMP label_name>
     stop            -   <STOP>
```

# Note
## wait 1 vs wait
```
wait 1  => <RPT 1>
wait    => micro instruction is left empty
```

`wait` is designed to be put before `jmp label_name`, because unison requires a
vector contains no micro-instructions before `<JMP label_name>`

## nop
`nop` means no-operation. the clock/data will keep `0`.
and `nop` on the right most can be ommited.
so the following
```
REG1, REG2, nop, nop, nop
```
can be simplified as
```
REG1, REG2
```
while
```
nop, nop, nop, REG1, REG2
```
cannot be simplified.

# example

```
DUT: 1, 2
ClockPinName: CLK_pin, CLK2_pin
DataPinName: DATA_pin, DATA2_pin
TriggerPinName: FX_TRIGGER_pin
ExtraPinName: VRAMP_pin=0
RegisterTable: regtable_dut1.csv, regtable_dut1.csv
WaveformRefRead: TS13MHz
WaveformRefWrite: TS26MHz

Label: Leak_LB_HPM
    LB_GMSK_HPM
    wait10
    wait200
    wait
    jmp L_TRX1
    
Label: Leak_HB_HPM
    HB_GMSK_HPM, nop
    wait10
    wait200
    
Label: L_TRX1
    nop, RESETALL
    nop, L_TRX0
    wait10
    trig
    wait200
    stop

```
