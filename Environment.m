classdef Environment < rl.env.MATLABEnvironment
    properties
        XLim = [-1 1]% 球水平运动范围 
        YLim = [-1.5 1.5]% 球竖直运动范围        
        BallRadius = 0.04% 球半径
        BallVelocity = [2 2] % 球速
        
        PaddleLength = 0.25% 板子长度             
        PaddleWidth = 0.02% 板子宽
        PaddleMass = 0.05 % 板子质量
        
        Damping = 0.01% 板子运动的阻尼系数     
        MaxForce = 5% 对板子施加水平正负方向的力度
             
        Ts = 0.025% 采样时间
        ImpactThreshold = 0.025 * 2      
        RewardForNotFalling = 0 % 球落在板子上时奖励
        RewardForStrike = 500; % 板子击球奖励
        PenaltyForFalling = -100%球掉落惩罚
        Hits = 0% 击球数
        State = [0 0 1 1 0 0 0]'% 初始化状态
    end
    
    properties (Access = private, Transient)
        Visualizer = []%可视化
    end
    
    properties(Access = protected)
        IsDone = false      %指示回合终止  
    end

    %% 
    methods              
        function this = Environment()
            ObservationInfo = rlNumericSpec([7 1]);
            ObservationInfo.Name = 'States';
            ObservationInfo.Description = 'ball_x, ball_y, paddle_dx, ball_dy, paddle_x, paddle_dx Fprev';
            
            ActionInfo = rlNumericSpec([1 1],'LowerLimit',-1,'UpperLimit',1);
            ActionInfo.Name = 'Action';
            ObservationInfo.Description = 'F';
            this = this@rl.env.MATLABEnvironment(ObservationInfo,ActionInfo);
        end
        
        function [Observation,Reward,IsDone,LoggedSignals] = step(this,Action)     
            LoggedSignals = [];
          
            Force = getForce(this,Action);           
            
            ball_x = this.State(1);
            ball_y = this.State(2);
            ball_dx = this.State(3);
            ball_dy = this.State(4);
            paddle_x = this.State(5);
            paddle_dx = this.State(6);
            
            IsDone = false;
            
            R = 0;
            
            ImpactThreshold_x = abs(this.Ts * ball_dx);
            ImpactThreshold_y = abs(this.Ts * ball_dy);
            
            % 当球到达x边界，以反向速度
            if (ball_x >= 0 && (ball_x + this.BallRadius) >= this.XLim(2) - ImpactThreshold_x) || ...
               (ball_x < 0 && (ball_x - this.BallRadius) <= this.XLim(1) + ImpactThreshold_x)     
                ball_dx = -ball_dx; 
            end
            % 当球到达y上边界 反向速度弹回
            if (ball_y >= 0 && (ball_y + this.BallRadius) >= this.YLim(2) - ImpactThreshold_y)    
                ball_dy = -ball_dy;  
            end
            % 当球倒下边界
            if (ball_y < 0 && (ball_y - this.BallRadius) <= this.YLim(1) + 0.5*this.PaddleWidth + ImpactThreshold_y)
                % 看球是否撞到板子
                if (ball_x >= paddle_x - 0.5*this.PaddleLength - ImpactThreshold_x) && (ball_x <= paddle_x + 0.5*this.PaddleLength + ImpactThreshold_x)
                    ball_dy = -ball_dy;
                    ball_dx = ball_dx + 0.1 * paddle_dx;
                    R = this.RewardForStrike;
                    this.Hits = this.Hits + 1;%撞到以反向速度弹回,hits+1，
                else
                    IsDone = true;
                    this.Hits = 0;%没撞到结束回合
                end
            end
           %% 球运动
            q1 = ball_x + ball_dx * this.Ts;  %更新速度
            q2 = ball_y + ball_dy * this.Ts; 
            q3 = ball_dx;  
            q4 = ball_dy;  
            
            %% 板子运动
            paddle_ddx = -this.Damping/this.PaddleMass * paddle_dx + Force/this.PaddleMass;
            q5 = paddle_x + paddle_dx * this.Ts + 0.5 * paddle_ddx * this.Ts^2;
            q6 = paddle_dx + paddle_ddx * this.Ts;  
            if q5 - 0.5*this.PaddleLength <= this.XLim(1)
                q5 = this.XLim(1) + 0.5*this.PaddleLength;
                q6 = 0;
            end
            if q5 + 0.5*this.PaddleLength >= this.XLim(2)
                q5 = this.XLim(2) - 0.5*this.PaddleLength;
                q6 = 0;
            end
            
            q7 = Force;
            
            Observation = [q1 q2 q3 q4 q5 q6 q7]';

        
            this.State = Observation;%状态更新
            this.IsDone = IsDone; 
            Reward = getReward(this,R);
            
            
            notifyEnvUpdated(this);
        end
        
        function InitialObservation = reset(this)
            %重置环境
                    
            if rand < 0.5
                LoggedSignal.State = [0 0 this.BallVelocity(1) this.BallVelocity(2) 0 0 0]';
            else
                ball_x = -0.1 + 0.2 * rand;
                ball_y = -0.1 + 0.2 * rand;
                ball_dx = this.BallVelocity(1);
                if rand < 0.5
                    ball_dx = -ball_dx;
                end
                ball_dy = this.BallVelocity(2);                
                paddle_x = -0.1 + 0.2 * rand;
                paddle_dx = -1 + 2 * rand;
                LoggedSignal.State = [ball_x ball_y ball_dx ball_dy paddle_x paddle_dx 0]';
            end

            InitialObservation = LoggedSignal.State;
            this.State = InitialObservation;
            
            this.Hits = 0;
            
            notifyEnvUpdated(this);
        end
        
        function y = saturate(this,u,lower,upper)
            y = u;
            if u - 0.5*this.PaddleLength <= lower
                y = lower + 0.5*this.PaddleLength;
            elseif u + 0.5*this.PaddleLength >= upper
                y = upper - 0.5*this.PaddleLength;
            end
        end
    end
    %% 
    methods               
        function force = getForce(this,action)
          
            force = this.MaxForce * action;           
        end
        
        function Reward = getReward(this,R)
            if ~this.IsDone
                Reward = R + this.RewardForNotFalling;
            else
                ball_x = this.State(1);
                paddle_x = this.State(5);
                Reward = R + this.PenaltyForFalling * abs(ball_x - paddle_x);
            end          
        end
        
        function varargout = plot(this)
            if isempty(this.Visualizer) || ~isvalid(this.Visualizer)
                this.Visualizer = Visualizer(this);
            else
                bringToFront(this.Visualizer);
            end
            if nargout
                varargout{1} = this.Visualizer;
            end
            envUpdatedCallback(this)
        end
        
       
        function set.State(this,state)
            validateattributes(state,{'numeric'},{'finite','real','vector','numel',7},'','State');
            this.State = double(state(:));
            notifyEnvUpdated(this);
        end
        function set.XLim(this,val)
            validateattributes(val,{'numeric'},{'finite','real','vector','numel',2},'','XLim');
            this.XLim = val;
            notifyEnvUpdated(this);
        end
        function set.YLim(this,val)
            validateattributes(val,{'numeric'},{'finite','real','vector','numel',2},'','YLim');
            this.YLim = val;
        end
        function set.BallRadius(this,val)
            validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','BallRadius');
            this.BallRadius = val;
        end
        function set.BallVelocity(this,val)
            validateattributes(val,{'numeric'},{'finite','real','positive','vector','numel',2},'','BallVelocity');
            this.BallVelocity = val;
        end
        function set.PaddleMass(this,val)
            validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','PaddleMass');
            this.PaddleMass = val;
        end
        function set.MaxForce(this,val)
            validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','MaxForce');
            this.MaxForce = val;
        end
        function set.Ts(this,val)
            validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','Ts');
            this.Ts = val;
        end
        function set.ImpactThreshold(this,val)
            validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','ImpactThreshold');
            this.ImpactThreshold = val;
        end
        function set.PaddleLength(this,val)
            validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','PaddleLength');
            this.PaddleLength = val;
        end
        function set.PaddleWidth(this,val)
            validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','PaddleWidth');
            this.PaddleWidth = val;
        end
        function set.RewardForNotFalling(this,val)
            validateattributes(val,{'numeric'},{'real','finite','scalar'},'','RewardForNotFalling');
            this.RewardForNotFalling = val;
        end
        function set.PenaltyForFalling(this,val)
            validateattributes(val,{'numeric'},{'real','finite','scalar'},'','PenaltyForFalling');
            this.PenaltyForFalling = val;
        end
    end
    
    methods (Access = protected)
        
        function envUpdatedCallback(this)
            
        end
    end
end
