.include "tn13Adef.inc"
; Предполагаемая тактовая частота - 4.8Мгц(можно еще 9.6Мгц)
; Fuses -	CKSEL0=1, CKSEL1=0, {4.8Mhz internal}
;			SUT0=0, SUT1=1, {14CK + 64 ms}
;			CKDIV8=1,
;			WDTON=1, EESAVE=1, RSTDISBL=1, {не трогать, оно не нужно}
;			BODLEVEL0=1, BODLEVEL1=1, {BOD disabled}
;			SPMEN=1
; 0 - programmed, 1 - unprogrammed.

; Константы
.EQU one_step_delay_ms  = 10 ; Длительность одного шага для переходов яркости в милисекундах
.EQU CPU_freq = 4800 ; Тактовая частота, килогерц
; Пересчет констант скорости перехода или времени
; T = N*256*0.01с/S - время перехода при заданной скорости S и количестве градаций N
; S = N*256*0.01с/T - скорость перехода при заданном времени T и количестве градаций N


; Общие регистры.
.DEF	ACCUM   = R25

; Определения

; Макро-функции...
; команды -
; 0 - SET_LED (level - 0..63)
; 1 - DELAY (value - 0..63)
; 2 - TRANSIT (destination level - 0..63, speed - 0..255)
; 3 -  1SDELAY (0..31 - delay, sec)
; 255 - END_PROGRAMM (loop to begin)

#define cmd_set_led	0
#define cmd_delay	1
#define cmd_transit	2
#define cmd_1sdelay	3
#define cmd_end		0xFF

#define	set_test1	SBI PORTB, 2
#define	clr_test1	CBI PORTB, 2
#define	set_test2	SBI PORTB, 3
#define	clr_test2	CBI PORTB, 3
#define	set_test3	SBI PORTB, 4
#define	clr_test3	CBI PORTB, 4
#define	toggle_test3	SBI PINB,  4

;Макросы
.include "macros.inc"

.macro expand_level ; расширение 6-битного аргумента до 8 бит путем умножения на 4.
  LSL	@0
  LSL	@0
.endmacro

.macro set_ch
  LDI	YH, High(channel@0) ; Указатель на RAM - адрес удваивать не надо
  LDI	YL, low (channel@0)
  LDI	CHANEL, @0
.endmacro

; Регистровые переменные
.DEF CHANEL		= R16  // Номер канала.
.DEF tempi		= R23
.DEF tempih		= R24
; Счетчики в регистрах
.DEF loopscount		= R19
.DEF tmp2		= R20 ; с возможностью непосредственной загрузки значения через LDI
.DEF loopscount2	= R21
.DEF status_led		= R1
; ======= Ячейки памяти  =========== RAM начинается с адреса 0x60-0x9F
.DSEG
channel1: .BYTE 9
channel2: .BYTE 9

#define cmd		0 // Текущая обрабатываемая команда
#define cmd_param1	1 // переменная для задержки / плавный переход параметр "до"
#define cmd_param2	2 // плавный переход параметр "c"
#define temp0	 	3 // значение субсчетчика плавного перехода для канала
#define cur_val		4
#define cmd_selL	5 // Указатель на текущую команду
#define cmd_selH	6
#define cmd_initL	7 // Начальное значение указателя данного канала
#define cmd_initH	8

.macro i_cmd ; Начальный адрес для указанного канала в его структуру по адресу Y в RAM
  LDI	ACCUM, high(prog@0*2) 
  STD	Y+cmd_initH, ACCUM
  LDI	ACCUM, low(prog@0*2)
  STD	Y+cmd_initL, ACCUM
.endmacro

.CSEG
.ORG 0
// Прерываний нет. Программа плоская.
;=====================================================
;                PROGRAM BEGIN THERE!!!
;=====================================================

RESET:
 set_io SPL, low(RAMEND)

 ; установить порты ввода-вывода
 set_io DDRB,   0b00011111  ; 1 - выход, 0 - вход.
 
; настройка таймера
;прескалер выставить на 8, Fast PWM частота будет 4.8Мгц/(8*512) ~ 1.1кГц

 set_io TCCR0A, 0b10100001	; режим таймера 01 - PWM(Phase Correct). Clear OC0A on Compare Match when up-counting.  
				; Set   OC0A on Compare Match when down-counting.
				; Set   OC0B on Compare Match when down-counting. 
 set_io TCCR0B, 0b00000010	; Счетчик работает c предделителем = 8.
 

; Собственно сам цикл программы
;========================================================================================================
;
;
;
;========================================================================================================

set_ch	1 ; Y = channel1, CHANEL = 1
i_cmd	1
rcall reset_cmd
rcall get_cmd

set_ch	2 ; Y = channel2, CHANEL = 2
i_cmd	2
rcall reset_cmd
rcall get_cmd

LOOP:

 set_ch 1
 set_test1
 rcall do_cmd
 clr_test1
 
 set_ch 2
 rcall do_cmd
 rcall delay_step
 
 inc	status_led
 LDI	ACCUM, 50
 CP	status_led, ACCUM
 BRNE LOOP
 toggle_test3 ; каждые 50 циклов опрокидываем порт, получим меандр частотой 1Гц.
 clr	status_led
 
RJMP LOOP

;========================================================================================================
do_cmd: // На входе Y - указывает на структуру переменных канала в памяти
        //  +cmd_selH, +cmd_selL - указатель на очередную выполняемую команду

 LDD	ACCUM,	Y+cmd

// Команда - установить яркость
;--------------
 CPI	ACCUM, cmd_set_led
 BRNE	check_delaycmd

 LDD	ACCUM,	Y+cmd_param1
 STD	Y+cur_val, ACCUM
 rcall	set_led_value ;ACCUM - value, CHANNEL - target

 rjmp next_cmd



// Команда - задержка
;--------------
check_delaycmd:
 CPI	ACCUM, cmd_delay
 BRNE	check_transit

 LDD	ACCUM,	Y+cmd_param1
 DEC	ACCUM
 STD	Y+cmd_param1, ACCUM
 BREQ	next_cmd ; Пока не дошло до нуля - продолжаем выполнять ЭТУ команду.
 rjmp 	exit_cmd



// Команда - переход яркости
;--------------
check_transit:
 CPI	ACCUM, cmd_transit
 BRNE	check_1sdelay

 LDD	ACCUM,	Y+cmd_param1
 LDD	tempi,	Y+cur_val
 CP	tempi,	ACCUM
 BREQ	next_cmd ; Переход окончен - переключаемся на следующую команду
 BRLO	transit_inc // target оказался больше чем текущее значение, нужен инкремент.

transit_dec:
 LDD	ACCUM,	Y+temp0
 LDD	tempi,	Y+cmd_param2
 ADD	ACCUM, tempi
 STD	Y+temp0, ACCUM
 BRCC	transit_no
 ; Декремент текущего значения светодиода
 LDD	ACCUM,	Y+cur_val
 DEC	ACCUM
 STD	Y+cur_val, ACCUM
 rcall	set_led_value
 rjmp	transit_no

transit_inc:
 LDD	ACCUM,	Y+temp0
 LDD	tempi,	Y+cmd_param2
 ADD	ACCUM, tempi
 STD	Y+temp0, ACCUM
 BRCC	transit_no
 ; Инкремент текущего значения светодиода
 LDD	ACCUM,	Y+cur_val
 INC	ACCUM
 STD	Y+cur_val, ACCUM
 rcall	set_led_value

transit_no:
 rjmp	exit_cmd


check_1sdelay:
 CPI	ACCUM, cmd_1sdelay
 BRNE	check_end
 LDD	tempih,	Y+cmd_param1 // Счетчик секунд
 CPI	tempih, 0
 BREQ	next_cmd
 LDD	tempi,	Y+temp0      // Субсчетчик для формирования секундных интервалов из отдельных шагов
 DEC	tempi
 BRNE	no_secdec
  DEC	tempih
  LDI	tempi, 100
no_secdec:
 STD	Y+temp0, tempi
 STD	Y+cmd_param1, tempih
 rjmp	exit_cmd


// Команда - конец программы
;--------------
check_end:

 rcall	reset_cmd
 rjmp	next_cmd

rjmp exit_cmd

next_cmd:
 rcall get_cmd
exit_cmd:
RET

;-----------------------------------------------------------------------------
set_led_value: ;(ACCUM - value, CHANNEL - target)

 CPI	CHANEL, 1
 BRNE	ch_no2
 OUT	OCR0A,	ACCUM
 rjmp	ch_end
ch_no2:
 OUT	OCR0B,	ACCUM
ch_end:

RET




;-----------------------------------------------------------------------------
reset_cmd:
 LDD	ACCUM, Y+cmd_initH // копируем поля начальных значений в текущий указатель.
 STD	Y+cmd_selH, ACCUM

 LDD	ACCUM, Y+cmd_initL
 STD	Y+cmd_selL, ACCUM
RET





;-----------------------------------------------------------------------------
get_cmd: ; указатель на команду, регистр команды, регистр параметра 0, регистр параметра 1
         // На входе Y - указатель на переменные нужного канала.
 LDD 	ZH, Y+cmd_selH
 LDD 	ZL, Y+cmd_selL
 LPM	ACCUM, Z+ ; Выборка кода команды
; Разделим команду на части
 MOV	tempi, ACCUM
 ANDI	tempi, 0x3F  ; оставляем только параметр1
 LSL	tempi ; параметр расширен до байта
 LSL	tempi
 STD	Y+cmd_param1, tempi ; Сохраним его как параметр1

  CLC
  rol	ACCUM
  rol	ACCUM
  rol	ACCUM

 ANDI	ACCUM, 0x03  ; оставляем только команду.
 STD	Y+cmd, ACCUM ; Сохраним команду

// Команда - переход яркости
;--------------
gc_transit:
 CPI	ACCUM, cmd_transit
 BRNE	gc_1sdelay
  ; необходимо считать еще один параметр
 LPM	tempi, Z+ ; Выборка второго параметра
 STD	Y+cmd_param2, tempi ; Сохраним его как параметр2
 CLR	tempi
 STD	Y+temp0, tempi ; Сбросим суб-счетчик
 rjmp	gcexit_cmd
 
 
 
gc_1sdelay:
 CPI	ACCUM, cmd_1sdelay
 BRNE	gcexit_cmd
 ;в tempi - остался первый параметр, сдвинутый на 2 бита
 ROL	tempi ; проверяем старший бит. если он равен 1 - значит это команда завершения.
 BRCS	gc_set_exit_com
 LSR	tempi
 LSR	tempi
 LSR	tempi
 STD	Y+cmd_param1, tempi
 LDI	ACCUM, 1 ; Начальное значение субсчетчика секунд(счетчик циклов)
 STD	Y+temp0, ACCUM
 RJMP	gcexit_cmd
 
gc_set_exit_com:
 SER	ACCUM
 STD	Y+cmd, ACCUM

gcexit_cmd:
 STD 	Y+cmd_selH, ZH ; Сохранить указатель на следующую команду
 STD 	Y+cmd_selL, ZL


RET







delay_step:  // задержка для одного шага в процедуре изменения яркости.
					; рассчитаем примерное количество тактов на 10мс -
					; N = 0.01c*4800000Гц = 48000
.EQU ds_inner_cycles = 256*4
.EQU ds_lpsc = (one_step_delay_ms * CPU_freq) / ds_inner_cycles

LDI		loopscount, ds_lpsc ; внешний цикл. 46*1024
l_loop1:
LDI		loopscount2, $00  ; 256 итераций. 1024 такта
l_loop2:
NOP					; 1*N
DEC 	loopscount2	; 1*N
BRNE	l_loop2     ; 2*N
DEC 	loopscount
BRNE	l_loop1

RET












; ###################################################################
;        ОПРЕДЕЛЕНИЯ ПРОГРАММНЫХ ПОСЛЕДОВАТЕЛЬНОСТЕЙ
; ###################################################################

.EQU p_set_led	= cmd_set_led<<6 ; Аргумент - 0..63
.EQU p_delay	= cmd_delay<<6	 ; Аргумент - 0..63 = x40мс
.EQU p_transit	= cmd_transit<<6 ; Аргумент - 0..63(яркость, градаций = x4), 0..255 (скорость)
.EQU p_1sdelay	= cmd_1sdelay<<6 ; Аргумент - 0..31
.EQU p_end		= cmd_end

prog1: .DB p_1sdelay+1 , p_set_led+0, p_transit+63, 255, p_transit+0, 127, p_delay+25, p_set_led+63, p_delay+2, p_set_led+0x00, p_delay+12, p_set_led+63, p_delay+2, p_set_led+0x00, p_1sdelay+9, p_end

prog2: .DB p_set_led+0, p_1sdelay+5, p_transit+0x3F, 0xAA, p_delay+0x10, p_set_led+0, p_delay+16, p_set_led+10, p_delay+16, p_set_led+0, p_delay+16, p_set_led+20, p_delay+0x10, p_end
