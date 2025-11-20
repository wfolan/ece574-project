module cordic_sine (
    input logic                clk,
    input logic                rst_n,
    input logic                start,
    input logic signed [31:0]  input_angle, // Fixed-point <int,15>
    output logic signed [31:0] sine_out,    // Fixed-point <int,15>
    output logic               valid
    );

    //local parameters
    localparam FRAC = 15;

    typedef logic signed [31:0] fixed; 

    //convert 1/K and pi/2 into fixed
    localparam fixed AG_CONST        = 32'sh00004DBA; // round((1/1.6467602578655)*2^15) = 19898

    localparam fixed PI_OVER_2       = 32'sh0000C90F; // π/2
    localparam fixed PI              = 32'sh00019220; // π
    localparam fixed THREE_PI_OVER_2 = 32'sh00025B30; // 3π/2
    localparam fixed TWO_PI          = 32'sh0003243F; // 2π

    //define arctan lookup table arctan(2^-i) for i = 0...15
    fixed Angles [0:FRAC];

    initial begin
        Angles[0]  = 32'sh00006488;
        Angles[1]  = 32'sh00003B59;
        Angles[2]  = 32'sh00001F5B;
        Angles[3]  = 32'sh00000FEB;
        Angles[4]  = 32'sh000007FD;
        Angles[5]  = 32'sh00000400;
        Angles[6]  = 32'sh00000200;
        Angles[7]  = 32'sh00000100;
        Angles[8]  = 32'sh00000080;
        Angles[9]  = 32'sh00000040;
        Angles[10] = 32'sh00000020;
        Angles[11] = 32'sh00000010;
        Angles[12] = 32'sh00000008;
        Angles[13] = 32'sh00000004;
        Angles[14] = 32'sh00000002;
        Angles[15] = 32'sh00000001;
    end

    //quadrant() returns which quadrant the input angle is in
    function automatic logic [1:0] quadrant(input fixed inangle);
        //reset if angle is greater than 2pi, breaks if input>4pi (unlikely)
        if (inangle > TWO_PI) 
            inangle = inangle - TWO_PI;

        if (inangle >= THREE_PI_OVER_2) 
            return 2'd3;
        else if (inangle >= PI) 
            return 2'd2;
        else if (inangle >= PI_OVER_2)     
            return 2'd1;
        else 
            return 2'd0;
    endfunction

    //angle_adj() adjusts angle to quadrant 0
    function automatic fixed angle_adj(input fixed inangle);
        //reset if angle is greater than 2pi, breaks if input>4pi (unlikely)
        if (inangle > TWO_PI) 
            inangle = inangle - TWO_PI;

        if (inangle >= THREE_PI_OVER_2)
            return TWO_PI - inangle; //Q3: reflect over x-axis
        else if (inangle >= PI)
            return inangle - PI; //Q2: reflect around π
        else if (inangle >= PI_OVER_2)
            return PI - inangle; //Q1: reflect over y-axis
        else
            return inangle; //Q0: already good
    endfunction


    fixed X, Y, angle_q0, angle_target, newX;
    logic [4:0] step;
    logic [1:0] quad;    // quadrant of original input

    //state machine
    typedef enum logic [1:0] {IDLE, ROTATE, DONE} state_t;
    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            valid <= 1'b0;
            sine_out <= 32'sd0;
            step <= 5'd0;
        end else begin
            state <= next_state;

            case (state)
                IDLE: begin
                    valid <= 1'b0;   // output not ready yet

                    if (start) begin
                        angle_q0 <= angle_adj(input_angle); //fold angle into q0
                        quad <= quadrant(input_angle); //determine output sign

                        X <= AG_CONST;
                        Y <= 32'sd0;
                        angle_target <= 32'sd0; // current rotation accumulator

                        step <= 5'd0;     // start at iteration 0
                    end
                end
                
                // one rotation step per clock
                ROTATE: begin
                    if (angle_q0 > angle_target) begin
                        // Rotate in + direction
                        X <= X - (Y >>> step);
                        Y <= (X >>> step) + Y;
                        angle_target <= angle_target + Angles[step];
                    end else begin
                        // Rotate in - direction
                        X <= X + (Y >>> step);
                        Y <= Y - (X >>> step);
                        angle_target <= angle_target - Angles[step];
                    end
                    step <= step + 1; //move to next angle
                end

                //sign correction
                DONE: begin
                    valid <= 1'b1;    // output ready

                    if (quad < 2)
                        sine_out <= Y;     // Q0, Q1 positive sine
                    else
                        sine_out <= -Y;    // Q2, Q3 negative sine
                end
            endcase
        end
    end

    //FSM control
    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (start) next_state = ROTATE;
            ROTATE:  if (step == FRAC+1) next_state = DONE; // Finished all iterations
            DONE: next_state = IDLE;
        endcase
    end
endmodule
