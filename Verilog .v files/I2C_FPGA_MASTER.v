module I2C_FPGA_MASTER
	#(
	parameter 							BIT_PER_SECOND=100000,
	parameter 							CLOCK_FREQUENCY=50000000,
	parameter 							CLKS_PER_BIT_LOG_2=$clog2(CLOCK_FREQUENCY/BIT_PER_SECOND)
	)
	(input 								IN_CLOCK,
	input 								IN_LAUNCH, 
	input [7:0] 						IN_DATA ,
	input [6:0] 						IN_ADRESS,
	input 								IN_WR, //1-READ, 0-WRITE
	input [7:0] 						IN_NUMBER_WR_BYTES, 
	input 								IN_RESET,								
	output reg 							OUT_TRANSMIT_DONE,
	output reg 							OUT_BYTE_WR_DONE,
	output reg 							OUT_WR_ACTIVE,
	output reg	[7:0] 				OUT_DATA,
	output reg 							OUT_ERROR,
	output reg 							PENULTIMATE_BIT_IN_TX_BYTE, 
	inout 								SDA,
	inout 								SCL
	);
	initial begin	
		OUT_TRANSMIT_DONE					=0;
		OUT_BYTE_WR_DONE					=0;
		OUT_WR_ACTIVE						=0;
		OUT_DATA								=0;
		OUT_ERROR							=0;
		PENULTIMATE_BIT_IN_TX_BYTE 	=0;
	end
	//Finite state machine (FSM)
	localparam CLKS_PER_BIT				=CLOCK_FREQUENCY/BIT_PER_SECOND;//must divide for 4
	localparam STATE_WAIT				=4'b0000;
	localparam STATE_START				=4'b0001;
	localparam STATE_WRITE_ADRESS		=4'b0010;
	localparam STATE_READ_ACK_1		=4'b0011;//after input adress device 
	localparam STATE_READ_ACK_2		=4'b0100;//after input data byte
	localparam STATE_WRITE_WR			=4'b0101;
	localparam STATE_WRITE_DATA		=4'b0110;
	localparam STATE_READ_DATA			=4'b0111;
	localparam STATE_WRITE_ACK			=4'b1000;
	localparam STATE_WRITE_STOP		=4'b1001;
	
	
	localparam INPUT						=1'b1;
	localparam OUTPUT						=1'b0;
	
	//internal registers
	reg [3:0] 								REG_FSM_STATE;
	reg [CLKS_PER_BIT_LOG_2:0]    	REG_CLOCK_COUNT;
	reg [7:0] 								REG_TRANSMIT_DATA;
	reg [6:0]								REG_ADRESS;
	reg [3:0]								REG_BIT_INDEX;
	reg 										REG_SDA_DATA; 
	reg										REG_SDA_IO_STATE;
	reg										REG_SCL_DATA;
	reg										REG_SCL_IO_STATE;
	reg										REG_WR;
	reg										REG_ACK;
	reg [7:0]								REG_NUMBER_WR_BYTES;
	initial begin
		REG_FSM_STATE				= STATE_WAIT;
		REG_CLOCK_COUNT			= 0;
		REG_TRANSMIT_DATA			= 8'b00000000;
		REG_ADRESS					= 0;
		REG_BIT_INDEX				= 7;
		REG_SDA_DATA				= 1;
		REG_SDA_IO_STATE			= INPUT;	
		REG_SCL_DATA				= 1;
		REG_SCL_IO_STATE			= INPUT;
		REG_WR						= 0;
		REG_ACK						= 1;
		REG_NUMBER_WR_BYTES		= 1;
	end
	assign SDA = REG_SDA_IO_STATE? 1'bz: REG_SDA_DATA? 1'bz:0;
	assign SCL = REG_SCL_IO_STATE? 1'bZ: REG_SCL_DATA? 1'bz:0;
	always @(posedge IN_CLOCK)
	begin 
		if (IN_RESET) //принудительный сброс
			REG_FSM_STATE=STATE_WRITE_STOP;//блокирующее
		case(REG_FSM_STATE)
			STATE_WAIT:
			begin
				OUT_ERROR=0;
				REG_SDA_DATA=1;
				REG_SDA_IO_STATE=INPUT;
				REG_SCL_DATA=1;
				REG_SCL_IO_STATE=INPUT;
				OUT_WR_ACTIVE=0;
				OUT_BYTE_WR_DONE=0;
				OUT_TRANSMIT_DONE=0;
				if(IN_LAUNCH) //запуск сообщения, если приемное устройсто отпустило SCL (умышленно не притягивает его к 0) 
				begin	
					OUT_WR_ACTIVE=1;
					REG_SDA_IO_STATE=OUTPUT;//состояние шины-вывод данных
					REG_SDA_DATA=0;//подтягиваем шину данных к нулю
					REG_SCL_IO_STATE=OUTPUT;//SCL настроен на вывод данных
					REG_TRANSMIT_DATA=IN_DATA;//запираем данные
					REG_ADRESS=IN_ADRESS;//запираем адрес
					REG_WR=IN_WR;
					REG_FSM_STATE=STATE_START;//переход к следующему состоянию автомата
					REG_NUMBER_WR_BYTES=IN_NUMBER_WR_BYTES;//защелкиваем число байт, сколько нужно прочитать/передать.
				end
			end
			STATE_START:
			begin
				
				if (REG_CLOCK_COUNT<CLKS_PER_BIT-2) //на один тик меньше
				begin
					if(REG_CLOCK_COUNT==CLKS_PER_BIT*3/4-1)
						REG_SCL_DATA=0;	
					REG_CLOCK_COUNT<=REG_CLOCK_COUNT+1'b1;
				end	
				else
				begin	
					REG_CLOCK_COUNT=0;
					REG_FSM_STATE=STATE_WRITE_ADRESS;
					REG_BIT_INDEX=6;
				end
			end
			STATE_WRITE_ADRESS:
			begin
				REG_SDA_DATA=REG_ADRESS[REG_BIT_INDEX];
				if (REG_CLOCK_COUNT<CLKS_PER_BIT-1)
				begin
					REG_CLOCK_COUNT<=REG_CLOCK_COUNT+1'b1;
					if(REG_CLOCK_COUNT==CLKS_PER_BIT/4)
						REG_SCL_DATA=!REG_SCL_DATA;
					else if (REG_CLOCK_COUNT==CLKS_PER_BIT*3/4)	
								REG_SCL_DATA=!REG_SCL_DATA;
				end
				else
				begin
					REG_CLOCK_COUNT <= 0;
					if(REG_BIT_INDEX>0)
						REG_BIT_INDEX=REG_BIT_INDEX-1'b1;
					else
					begin
						REG_BIT_INDEX=7;
						REG_FSM_STATE=STATE_WRITE_WR;
					end
				end
			end
			STATE_WRITE_WR:
			begin
				REG_SDA_DATA=REG_WR;
				if (REG_CLOCK_COUNT<CLKS_PER_BIT)
				begin
					REG_CLOCK_COUNT<=REG_CLOCK_COUNT+1'b1;
					if(REG_CLOCK_COUNT==CLKS_PER_BIT/4)
						REG_SCL_DATA=!REG_SCL_DATA;
					else if (REG_CLOCK_COUNT==CLKS_PER_BIT*3/4)	
								REG_SCL_DATA=!REG_SCL_DATA;
				end
				else
				begin
					REG_CLOCK_COUNT=0;
					REG_FSM_STATE=STATE_READ_ACK_1;
					REG_SDA_IO_STATE=INPUT;
				end
			end
			STATE_READ_ACK_1:
			begin
				if (REG_CLOCK_COUNT<CLKS_PER_BIT-2)
				begin
					REG_CLOCK_COUNT<=REG_CLOCK_COUNT+1'b1;
					if(REG_CLOCK_COUNT==CLKS_PER_BIT/4-1)
						REG_SCL_DATA=!REG_SCL_DATA;
					else if (REG_CLOCK_COUNT==CLKS_PER_BIT/2)
								REG_ACK=SDA;
							else if (REG_CLOCK_COUNT==CLKS_PER_BIT*3/4-1)	
										REG_SCL_DATA=!REG_SCL_DATA;
				end
				else
				begin
					REG_CLOCK_COUNT=0;
					if(!REG_ACK)
					begin
						REG_FSM_STATE			<= (REG_WR==INPUT)? STATE_READ_DATA:STATE_WRITE_DATA;
						REG_BIT_INDEX			<=7;
						REG_NUMBER_WR_BYTES	<=REG_NUMBER_WR_BYTES-1'b1;
					end
					else 
					begin
						REG_FSM_STATE		<=STATE_WAIT;
						OUT_ERROR			<=1;
						OUT_TRANSMIT_DONE	<=1;//окончание передачи всей посылки		
						
					end
				end
			end
			STATE_WRITE_DATA:
			begin
				OUT_BYTE_WR_DONE=0;
				REG_SDA_IO_STATE=OUTPUT;
				REG_SDA_DATA=REG_TRANSMIT_DATA[REG_BIT_INDEX];
				if (REG_CLOCK_COUNT < CLKS_PER_BIT-1)              
            begin
					REG_CLOCK_COUNT<=REG_CLOCK_COUNT+1'b1;
					if(REG_CLOCK_COUNT==CLKS_PER_BIT/4)
						REG_SCL_DATA=!REG_SCL_DATA;
					//else if (REG_CLOCK_COUNT==CLKS_PER_BIT/2&&SCL==0)
							//	REG_BIT_INDEX =REG_BIT_INDEX +1;
							else if (REG_CLOCK_COUNT==CLKS_PER_BIT*3/4)	
										REG_SCL_DATA=!REG_SCL_DATA;
				end         
            else
				begin
					REG_CLOCK_COUNT = 0;
               if (REG_BIT_INDEX >0)
						begin
							REG_BIT_INDEX <= REG_BIT_INDEX - 1'b1;   
							if (REG_BIT_INDEX==1)
								PENULTIMATE_BIT_IN_TX_BYTE<=1;
						end
						else
                  begin
							REG_BIT_INDEX 							<= 7;
							REG_FSM_STATE 							<=STATE_READ_ACK_2;	
							PENULTIMATE_BIT_IN_TX_BYTE			<=0;
                  end
				end
			end	
			STATE_READ_ACK_2:
			begin
				REG_SDA_IO_STATE=INPUT;
				if (REG_CLOCK_COUNT<CLKS_PER_BIT-1)
				begin
					REG_CLOCK_COUNT<=REG_CLOCK_COUNT+1'b1;
					if(REG_CLOCK_COUNT==CLKS_PER_BIT/4)
						REG_SCL_DATA=!REG_SCL_DATA;
					else if (REG_CLOCK_COUNT==CLKS_PER_BIT/2)
								REG_ACK=SDA;
							else if (REG_CLOCK_COUNT==CLKS_PER_BIT*3/4)	
										REG_SCL_DATA=!REG_SCL_DATA;
				end
				else
				begin
					REG_CLOCK_COUNT			<=0;
					OUT_BYTE_WR_DONE			<=1;
					if(!REG_ACK)
					begin
						REG_BIT_INDEX			<= 7;
						if(REG_NUMBER_WR_BYTES>0)
						begin
							REG_NUMBER_WR_BYTES=REG_NUMBER_WR_BYTES-1'b1;
							//защелкиваем новый пакет данных и сообщаем, что байт отправлен+переход снова на запись байта					
							REG_TRANSMIT_DATA		<= IN_DATA;
							REG_FSM_STATE			<= STATE_WRITE_DATA;
						end
						else
						begin//пора завершать передачу		
							REG_FSM_STATE			<=STATE_WRITE_STOP;
						end
					end
					else 
					begin
						REG_FSM_STATE			<=STATE_WAIT;//ошибка
						OUT_ERROR				<=1;			//ошибка	
						OUT_TRANSMIT_DONE		<=1;//окончание передачи всей посылки		
					end
				end
			end
			STATE_READ_DATA:
			begin
				OUT_BYTE_WR_DONE=0;
				REG_SDA_IO_STATE=INPUT;
				if (REG_CLOCK_COUNT<CLKS_PER_BIT-1)
				begin
					REG_CLOCK_COUNT<=REG_CLOCK_COUNT+1'b1;
					if(REG_CLOCK_COUNT==CLKS_PER_BIT/4)
						REG_SCL_DATA=!REG_SCL_DATA;
					else if (REG_CLOCK_COUNT==CLKS_PER_BIT/2)
								OUT_DATA[REG_BIT_INDEX]=SDA;						
							else if (REG_CLOCK_COUNT==CLKS_PER_BIT*3/4)	
										REG_SCL_DATA=!REG_SCL_DATA;
				end
				else
				begin
					REG_CLOCK_COUNT <= 0;
					if(REG_BIT_INDEX>0)
						REG_BIT_INDEX=REG_BIT_INDEX-1'b1;
					else
					begin
						REG_BIT_INDEX=7;
						REG_FSM_STATE <=STATE_WRITE_ACK;
					end
				end
			end
			STATE_WRITE_ACK:
			begin
				REG_SDA_IO_STATE=OUTPUT;
				REG_SDA_DATA=0;//ACK bit
				if (REG_CLOCK_COUNT<CLKS_PER_BIT-1)
				begin
					REG_CLOCK_COUNT<=REG_CLOCK_COUNT+1'b1;
					if(REG_CLOCK_COUNT==CLKS_PER_BIT/4)
						REG_SCL_DATA=!REG_SCL_DATA;		
					else if (REG_CLOCK_COUNT==CLKS_PER_BIT*3/4)	
								REG_SCL_DATA=!REG_SCL_DATA;
				end
				else
				begin
					REG_CLOCK_COUNT=0;
					OUT_BYTE_WR_DONE=1;
					if(REG_NUMBER_WR_BYTES>0)
					begin
						//сообщаем, что байт отправлен+переход снова на запись байта
						REG_NUMBER_WR_BYTES=REG_NUMBER_WR_BYTES-1'b1;
						REG_FSM_STATE=STATE_WRITE_DATA;
						REG_BIT_INDEX=7;
					end
					else
					begin//пора завершать передачу	
						REG_FSM_STATE=STATE_WRITE_STOP;
					end
				end
			end
			STATE_WRITE_STOP:
			begin
				OUT_BYTE_WR_DONE=0;
				REG_SDA_IO_STATE=OUTPUT;
				REG_SDA_DATA=0;
				if (REG_CLOCK_COUNT<CLKS_PER_BIT)
				begin
					REG_CLOCK_COUNT<=REG_CLOCK_COUNT+1'b1;
					if(REG_CLOCK_COUNT==CLKS_PER_BIT*7/8)
						REG_SCL_DATA=!REG_SCL_DATA;
				end
				else
				begin
					REG_CLOCK_COUNT=0;
					REG_SDA_IO_STATE=INPUT; //отпускаем шину
					REG_SDA_DATA=1;//НА ВСЯКИЙ СЛУЧАЙ
					OUT_TRANSMIT_DONE=1;//окончание передачи всей посылки		
					REG_FSM_STATE<=STATE_WAIT;
				end
			end
		endcase
	end
endmodule
