[CmdletBinding()]
param([switch]$TestMode)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (-not ('MonitorModeDpi.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MonitorModeDpi {
    public static class NativeMethods {
        [DllImport("user32.dll")]
        public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    }
}
'@
}
try { [void][MonitorModeDpi.NativeMethods]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch { }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
if (-not ('MonitorModeGlass.LiquidGlassController' -as [type])) {
    Add-Type -ReferencedAssemblies PresentationCore,PresentationFramework,WindowsBase,System.Xaml -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Media3D;
namespace MonitorModeGlass {
    public sealed class LiquidGlassLayer : FrameworkElement {
        double cx,cy,width,height,velocityX,velocityY,scale;bool moving;readonly int renderTier;VisualBrush backdropBrush;Brush volumeFill,innerGlow;
        Pen scatterFar,scatterMid,scatterNear,coolFringe,warmFringe,edge,inner,specular,shade,rimPen;RadialGradientBrush rimBrush;
        static Color ColorOf(string value){return (Color)ColorConverter.ConvertFromString(value);}
        static SolidColorBrush BrushOf(string value){SolidColorBrush b=new SolidColorBrush(ColorOf(value));b.Freeze();return b;}
        static GradientStop Stop(string color,double offset){return new GradientStop(ColorOf(color),offset);}
        static Pen PenOf(string color,double size){Pen p=new Pen(BrushOf(color),size);p.Freeze();return p;}
        static LinearGradientBrush Gradient(string first,string middle,string last){LinearGradientBrush b=new LinearGradientBrush();b.StartPoint=new Point(0,0);b.EndPoint=new Point(1,1);b.GradientStops.Add(Stop(first,0));b.GradientStops.Add(Stop(middle,.46));b.GradientStops.Add(Stop(last,1));b.Freeze();return b;}
        static Pen GradientPen(string first,string second,double size){LinearGradientBrush b=Gradient(first,second,second);Pen p=new Pen(b,size);p.Freeze();return p;}
        public LiquidGlassLayer(){IsHitTestVisible=false;Focusable=false;SnapsToDevicePixels=true;renderTier=RenderCapability.Tier>>16;SetTheme("Dark");}
        public void SetBackdrop(Visual visual){backdropBrush=visual==null?null:new VisualBrush(visual){ViewboxUnits=BrushMappingMode.Absolute,Stretch=Stretch.Fill,AlignmentX=AlignmentX.Center,AlignmentY=AlignmentY.Center};InvalidateVisual();}
        public void SetTheme(string theme){string far,mid,near,cool,warm,main,inside,shine,dark,rim,rimMid,fillA,fillB,fillC,glowA,glowB;
            if(theme=="Light"){far="#105276A8";mid="#1B5E83B2";near="#31749AC5";cool="#9AC9EAFF";warm="#72EAB7D5";main="#E8FFFFFF";inside="#74738BA8";shine="#FFFFFFFF";dark="#3A536B88";rim="#E8FFFFFF";rimMid="#6679AFFF";fillA="#2CFFFFFF";fillB="#10DCEBFA";fillC="#1C5E7895";glowA="#30FFFFFF";glowB="#0679AFFF";}
            else if(theme=="Pink"){far="#10E36BA5";mid="#20D879BB";near="#38E998C6";cool="#9AD9DEFF";warm="#A0FF9BCB";main="#F0FFF7FC";inside="#82C287AE";shine="#FFFFFFFF";dark="#46754763";rim="#F0FFDDF0";rimMid="#76D85C93";fillA="#3EFFF7FC";fillB="#16F3C9E1";fillC="#284B2D52";glowA="#50FFFFFF";glowB="#0CD85C93";}
            else{far="#104F78AD";mid="#205D8FC5";near="#346FAEDB";cool="#A1C9ECFF";warm="#7CD6A4C8";main="#E4F6FBFF";inside="#766C90B2";shine="#FFFFFFFF";dark="#58101928";rim="#E8E8F7FF";rimMid="#747DA6D2";fillA="#34FFFFFF";fillB="#102B4B68";fillC="#32101928";glowA="#44FFFFFF";glowB="#087DA6D2";}
            scatterFar=PenOf(far,4.4);scatterMid=PenOf(mid,2.7);scatterNear=PenOf(near,1.4);coolFringe=PenOf(cool,.82);warmFringe=PenOf(warm,.78);edge=PenOf(main,1.08);inner=PenOf(inside,.74);specular=GradientPen(shine,"#00FFFFFF",1.35);shade=GradientPen("#00000000",dark,1.08);volumeFill=Gradient(fillA,fillB,fillC);innerGlow=Gradient(glowA,"#00FFFFFF",glowB);
            rimBrush=new RadialGradientBrush();rimBrush.MappingMode=BrushMappingMode.Absolute;rimBrush.GradientStops.Add(Stop(rim,0));rimBrush.GradientStops.Add(Stop(rimMid,.34));rimBrush.GradientStops.Add(Stop("#00000000",1));rimPen=new Pen(rimBrush,1.75);InvalidateVisual();}
        internal void UpdateLens(double centerX,double centerY,double baseWidth,double baseHeight,double vx,double vy,double newScale,double opacity,bool isMoving,Point mouse){cx=centerX;cy=centerY;width=baseWidth;height=baseHeight;velocityX=vx;velocityY=vy;scale=newScale;moving=isMoving;Opacity=opacity;if(rimBrush!=null){rimBrush.Center=mouse;rimBrush.GradientOrigin=mouse;rimBrush.RadiusX=Math.Max(82,baseWidth*.58);rimBrush.RadiusY=Math.Max(58,baseHeight*.92);}InvalidateVisual();}
        static void DrawRim(DrawingContext dc,Rect rect,double radius,Pen pen){dc.DrawRoundedRectangle(null,pen,rect,radius,radius);}
        protected override void OnRender(DrawingContext dc){base.OnRender(dc);if(width<=0||height<=0||Opacity<=.002)return;double speed=Math.Sqrt(velocityX*velocityX+velocityY*velocityY),nx=speed>.01?Math.Abs(velocityX)/speed:0,ny=speed>.01?Math.Abs(velocityY)/speed:0,amount=moving?Math.Min(.042,speed*.00005):0;
            double drawW=width*scale*(1+amount*(nx*nx-.42*ny*ny)),drawH=height*scale*(1+amount*(ny*ny-.42*nx*nx));Rect r=new Rect(cx-drawW*.5,cy-drawH*.5,drawW,drawH);double radius=Math.Min(17*scale,r.Height*.5);
            if(renderTier>=2){Rect a=r;a.Inflate(3.6,3.6);DrawRim(dc,a,radius+3.6,scatterFar);a=r;a.Inflate(2,2);DrawRim(dc,a,radius+2,scatterMid);}if(renderTier>=1){Rect a=r;a.Inflate(.85,.85);DrawRim(dc,a,radius+.85,scatterNear);double dx=.38+(speed>.01?velocityX/speed*.26:0),dy=.38+(speed>.01?velocityY/speed*.26:0);Rect c=r;c.Offset(-dx,-dy);Rect w=r;w.Offset(dx,dy);DrawRim(dc,c,radius,coolFringe);DrawRim(dc,w,radius,warmFringe);}
            if(backdropBrush!=null&&renderTier>=1){double magnify=moving?1.024:1.014,sw=r.Width/magnify,sh=r.Height/magnify,shift=Math.Min(1.1,speed*.0007),sx=speed>.01?velocityX/speed*shift:0,sy=speed>.01?velocityY/speed*shift:0;backdropBrush.Viewbox=new Rect(cx-sw*.5-sx,cy-sh*.5-sy,sw,sh);dc.DrawRoundedRectangle(backdropBrush,null,r,radius,radius);}
            dc.DrawRoundedRectangle(volumeFill,null,r,radius,radius);Rect glow=r;glow.Inflate(-1,-1);if(glow.Width>0&&glow.Height>0)dc.DrawRoundedRectangle(innerGlow,null,glow,Math.Max(1,radius-1),Math.Max(1,radius-1));DrawRim(dc,r,radius,edge);DrawRim(dc,r,radius,specular);DrawRim(dc,r,radius,shade);Rect insideRect=r;insideRect.Inflate(-1.45,-1.45);if(insideRect.Width>0&&insideRect.Height>0)DrawRim(dc,insideRect,Math.Max(1,radius-1.45),inner);if(renderTier>=1)DrawRim(dc,r,radius,rimPen);}
    }
    public sealed class LiquidGlassController : IDisposable {
        enum Phase{Hidden,Appearing,Holding,Transitioning,Fading}
        const double EntryScale=.84;readonly Window window;readonly FrameworkElement root;readonly LiquidGlassLayer layer;readonly HashSet<Button> buttons=new HashSet<Button>();readonly Stopwatch clock=Stopwatch.StartNew();
        Button currentTarget,pendingTarget;Rect pendingGoal;Point mouse;double cx,cy,w,h,vcx,vcy,vw,vh,scale=EntryScale,vScale,opacity,vOpacity,lastTime,leaveAt=-1,travelDistance,travelDepth;bool rendering,disposed;Phase phase=Phase.Hidden;
        readonly MouseEventHandler mouseMoveHandler,mouseLeaveHandler;readonly EventHandler renderingHandler;readonly DependencyPropertyChangedEventHandler enabledHandler;
        public LiquidGlassController(Window window,FrameworkElement root,LiquidGlassLayer layer){this.window=window;this.root=root;this.layer=layer;mouseMoveHandler=OnMouseMove;mouseLeaveHandler=OnMouseLeave;renderingHandler=OnRendering;enabledHandler=OnEnabledChanged;window.PreviewMouseMove+=mouseMoveHandler;root.MouseLeave+=mouseLeaveHandler;}
        public void Register(Button button){if(button!=null&&buttons.Add(button))button.IsEnabledChanged+=enabledHandler;}
        public void SetTheme(string theme){layer.SetTheme(theme);}
        public void Hide(){BeginExit();}
        void OnEnabledChanged(object sender,DependencyPropertyChangedEventArgs e){Button b=sender as Button;if(b!=null&&!b.IsEnabled&&(b==currentTarget||b==pendingTarget))BeginExit();}
        void OnMouseLeave(object sender,MouseEventArgs e){if(phase!=Phase.Hidden&&leaveAt<0)leaveAt=clock.Elapsed.TotalSeconds+.075;StartRendering();}
        static Button FindButton(DependencyObject source){DependencyObject node=source;while(node!=null){Button button=node as Button;if(button!=null)return button;if(node is Visual||node is Visual3D)node=VisualTreeHelper.GetParent(node);else{FrameworkContentElement content=node as FrameworkContentElement;node=content==null?null:content.Parent;}}return null;}
        bool TryGetGoal(Button button,out Rect result){result=Rect.Empty;if(button==null||!button.IsEnabled)return false;button.ApplyTemplate();FrameworkElement anchor=button.Template.FindName("GlassAnchor",button) as FrameworkElement;if(anchor==null||anchor.ActualWidth<=0||anchor.ActualHeight<=0)return false;try{result=anchor.TransformToAncestor(root).TransformBounds(new Rect(0,0,anchor.ActualWidth,anchor.ActualHeight));return true;}catch(InvalidOperationException){return false;}}
        void OnMouseMove(object sender,MouseEventArgs e){if(disposed)return;mouse=e.GetPosition(root);Button button=FindButton(e.OriginalSource as DependencyObject);if(button!=null&&buttons.Contains(button)&&button.IsEnabled){leaveAt=-1;RequestTarget(button);}else if(phase!=Phase.Hidden&&leaveAt<0){leaveAt=clock.Elapsed.TotalSeconds+.075;StartRendering();}}
        static double Smooth(double value){value=Math.Max(0,Math.Min(1,value));return value*value*value*(value*(value*6-15)+10);}
        void RequestTarget(Button button){Rect next;if(!TryGetGoal(button,out next))return;pendingGoal=next;if(phase==Phase.Hidden){currentTarget=pendingTarget=button;cx=next.X+next.Width*.5;cy=next.Y+next.Height*.5;w=next.Width;h=next.Height;scale=EntryScale;opacity=0;phase=Phase.Appearing;StartRendering();return;}if(button==pendingTarget&&phase!=Phase.Fading){StartRendering();return;}pendingTarget=button;double gx=next.X+next.Width*.5,gy=next.Y+next.Height*.5;travelDistance=Math.Max(1,Math.Sqrt((cx-gx)*(cx-gx)+(cy-gy)*(cy-gy)));travelDepth=.045+.115*Smooth(Math.Min(1,travelDistance/260));phase=Phase.Transitioning;StartRendering();}
        void BeginExit(){leaveAt=-1;pendingTarget=null;if(phase==Phase.Hidden)return;phase=Phase.Fading;StartRendering();}
        void StartRendering(){if(rendering||disposed)return;lastTime=clock.Elapsed.TotalSeconds;CompositionTarget.Rendering+=renderingHandler;rendering=true;}
        static void Spring(ref double value,ref double velocity,double goal,double omega,double damping,double dt){double f=1+2*dt*damping*omega,oo=omega*omega,hoo=dt*oo,hhoo=dt*hoo,det=1/(f+hhoo),old=value;value=(f*old+dt*velocity+hhoo*goal)*det;velocity=(velocity+hoo*(goal-old))*det;}
        void TrackGoal(double dt,double omega,double damping){double gx=pendingGoal.X+pendingGoal.Width*.5,gy=pendingGoal.Y+pendingGoal.Height*.5;Spring(ref cx,ref vcx,gx,omega,damping,dt);Spring(ref cy,ref vcy,gy,omega,damping,dt);Spring(ref w,ref vw,pendingGoal.Width,omega+2,damping,dt);Spring(ref h,ref vh,pendingGoal.Height,omega+2,damping,dt);}
        void Step(double dt){if(phase==Phase.Transitioning){double gx=pendingGoal.X+pendingGoal.Width*.5,gy=pendingGoal.Y+pendingGoal.Height*.5,remaining=Math.Sqrt((cx-gx)*(cx-gx)+(cy-gy)*(cy-gy)),progress=Smooth(1-Math.Min(1,remaining/travelDistance)),wave=4*progress*(1-progress);TrackGoal(dt,32,.92);Spring(ref scale,ref vScale,1-travelDepth*wave,40,1,dt);if(remaining<.5&&Math.Sqrt(vcx*vcx+vcy*vcy)<9&&Math.Abs(w-pendingGoal.Width)+Math.Abs(h-pendingGoal.Height)<.35){currentTarget=pendingTarget;phase=Phase.Holding;}}
            else if(phase==Phase.Appearing||phase==Phase.Holding){TrackGoal(dt,phase==Phase.Appearing?32:28,phase==Phase.Appearing?.82:1);Spring(ref scale,ref vScale,1,phase==Phase.Appearing?31:34,phase==Phase.Appearing?.82:1,dt);if(phase==Phase.Appearing&&Math.Abs(scale-1)<.006&&Math.Abs(vScale)<.07)phase=Phase.Holding;}
            else if(phase==Phase.Fading)Spring(ref scale,ref vScale,.76,32,1,dt);double opacityGoal=phase==Phase.Fading||phase==Phase.Hidden?0:1;Spring(ref opacity,ref vOpacity,opacityGoal,38,1,dt);if(opacity<=0){opacity=0;if(vOpacity<0)vOpacity=0;}else if(opacity>=1){opacity=1;if(vOpacity>0)vOpacity=0;}}
        void OnRendering(object sender,EventArgs args){double now=clock.Elapsed.TotalSeconds;if(leaveAt>0&&now>=leaveAt)BeginExit();Rect fresh;if(pendingTarget!=null){if(TryGetGoal(pendingTarget,out fresh))pendingGoal=fresh;else BeginExit();}double total=Math.Max(.001,Math.Min(.05,now-lastTime));lastTime=now;int steps=Math.Min(6,Math.Max(1,(int)Math.Ceiling(total/(1.0/120.0))));double dt=total/steps;for(int i=0;i<steps;i++)Step(dt);double drawScale=Math.Max(.74,Math.Min(1.025,scale));layer.UpdateLens(cx,cy,w,h,vcx,vcy,drawScale,Math.Max(0,Math.Min(1,opacity)),phase==Phase.Transitioning,mouse);
            if(phase==Phase.Fading&&opacity<.004){phase=Phase.Hidden;currentTarget=null;scale=EntryScale;opacity=0;layer.Opacity=0;StopRendering();}else if(phase==Phase.Holding&&Math.Abs(vcx)+Math.Abs(vcy)+Math.Abs(vw)+Math.Abs(vh)+Math.Abs(vScale)<.55&&Math.Abs(scale-1)<.004&&Math.Abs(opacity-1)<.003)StopRendering();}
        void StopRendering(){if(!rendering)return;CompositionTarget.Rendering-=renderingHandler;rendering=false;}
        public void Dispose(){if(disposed)return;disposed=true;StopRendering();window.PreviewMouseMove-=mouseMoveHandler;root.MouseLeave-=mouseLeaveHandler;foreach(Button b in buttons)b.IsEnabledChanged-=enabledHandler;buttons.Clear();currentTarget=pendingTarget=null;}
    }
}
'@
}

$CoreScript = Join-Path $PSScriptRoot 'Monitor-1280x880.ps1'
if (-not (Test-Path -LiteralPath $CoreScript)) {
    [System.Windows.MessageBox]::Show('找不到核心脚本：' + $CoreScript, '显示模式控制台', 'OK', 'Error') | Out-Null
    exit 2
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="显示模式控制台" Width="1100" Height="850" MinWidth="920" MinHeight="700"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResizeWithGrip"
        UseLayoutRounding="True" SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="ClearType" TextOptions.TextHintingMode="Fixed"
        Background="{DynamicResource WindowBackgroundBrush}" Foreground="{DynamicResource PrimaryTextBrush}" FontFamily="Microsoft YaHei UI">
  <Window.Resources>
    <LinearGradientBrush x:Key="WindowBackgroundBrush" StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#090A0D" Offset="0"/><GradientStop Color="#121827" Offset="1"/></LinearGradientBrush>
    <LinearGradientBrush x:Key="IOSSurface" StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#24262C" Offset="0"/><GradientStop Color="#171B22" Offset="1"/></LinearGradientBrush>
    <SolidColorBrush x:Key="IOSBorder" Color="#28FFFFFF"/>
    <SolidColorBrush x:Key="PrimaryTextBrush" Color="#F5F5F7"/>
    <SolidColorBrush x:Key="SecondaryTextBrush" Color="#AEB9C6"/>
    <SolidColorBrush x:Key="MutedTextBrush" Color="#748394"/>
    <SolidColorBrush x:Key="CardBrush" Color="#E6101520"/>
    <SolidColorBrush x:Key="LogBrush" Color="#F2080D13"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#64B5F6"/>
    <SolidColorBrush x:Key="PanelBrush" Color="#F0101520"/>
    <SolidColorBrush x:Key="ControlBrush" Color="#FF111923"/>
    <SolidColorBrush x:Key="ControlHoverBrush" Color="#FF263544"/>
    <SolidColorBrush x:Key="SeparatorBrush" Color="#FF263241"/>
    <SolidColorBrush x:Key="LogAlternateBrush" Color="#FF0B1016"/>
    <SolidColorBrush x:Key="SelectedBrush" Color="#FF151E27"/>
    <SolidColorBrush x:Key="SuccessBrush" Color="#FF55D69E"/>
    <SolidColorBrush x:Key="WarningBrush" Color="#FFE3B55B"/>
    <SolidColorBrush x:Key="ErrorBrush" Color="#FFE06B76"/>
    <Style x:Key="IOSButtonStyle" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource PrimaryTextBrush}"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="17"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Padding" Value="20,13"/>
      <Setter Property="MinHeight" Value="68"/><Setter Property="BorderThickness" Value="0"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Grid x:Name="TemplateRoot" Margin="2">
          <Border x:Name="GlassAnchor" Background="Transparent" CornerRadius="17" IsHitTestVisible="False"/>
          <Grid x:Name="MotionSurface" RenderTransformOrigin="0.5,0.5">
            <Grid.RenderTransform><ScaleTransform x:Name="PressScale"/></Grid.RenderTransform>
            <Border x:Name="Surface" CornerRadius="17" Background="{DynamicResource IOSSurface}" BorderBrush="{DynamicResource IOSBorder}" BorderThickness="1">
              <Border x:Name="PressWash" CornerRadius="17" Background="#18FFFFFF" Opacity="0" IsHitTestVisible="False"/>
            </Border>
          </Grid>
          <ContentPresenter x:Name="ButtonContent" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="5"/>
          <Border x:Name="FocusRing" Margin="3" CornerRadius="14" BorderBrush="#A064D2FF" BorderThickness="2" Opacity="0" IsHitTestVisible="False"/>
          <VisualStateManager.VisualStateGroups>
            <VisualStateGroup x:Name="CommonStates">
              <VisualStateGroup.Transitions>
                <VisualTransition To="Pressed" GeneratedDuration="0:0:0.055"><VisualTransition.GeneratedEasingFunction><QuarticEase EasingMode="EaseOut"/></VisualTransition.GeneratedEasingFunction></VisualTransition>
                <VisualTransition From="Pressed" GeneratedDuration="0:0:0.16"><VisualTransition.GeneratedEasingFunction><BackEase Amplitude="0.10" EasingMode="EaseOut"/></VisualTransition.GeneratedEasingFunction></VisualTransition>
                <VisualTransition GeneratedDuration="0:0:0.08"><VisualTransition.GeneratedEasingFunction><CubicEase EasingMode="EaseOut"/></VisualTransition.GeneratedEasingFunction></VisualTransition>
              </VisualStateGroup.Transitions>
              <VisualState x:Name="Normal"><Storyboard><DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleX" To="1" Duration="0"/><DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleY" To="1" Duration="0"/><DoubleAnimation Storyboard.TargetName="PressWash" Storyboard.TargetProperty="Opacity" To="0" Duration="0"/></Storyboard></VisualState>
              <VisualState x:Name="MouseOver"><Storyboard><DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleX" To="1" Duration="0"/><DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleY" To="1" Duration="0"/><DoubleAnimation Storyboard.TargetName="PressWash" Storyboard.TargetProperty="Opacity" To="0" Duration="0"/></Storyboard></VisualState>
              <VisualState x:Name="Pressed"><Storyboard><DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleX" To="0.98" Duration="0"/><DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleY" To="0.98" Duration="0"/><DoubleAnimation Storyboard.TargetName="PressWash" Storyboard.TargetProperty="Opacity" To="1" Duration="0"/></Storyboard></VisualState>
              <VisualState x:Name="Disabled"><Storyboard><DoubleAnimation Storyboard.TargetName="TemplateRoot" Storyboard.TargetProperty="Opacity" To="0.38" Duration="0"/></Storyboard></VisualState>
            </VisualStateGroup>
            <VisualStateGroup x:Name="FocusStates"><VisualState x:Name="Focused"><Storyboard><DoubleAnimation Storyboard.TargetName="FocusRing" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.1"/></Storyboard></VisualState><VisualState x:Name="Unfocused"/></VisualStateGroup>
          </VisualStateManager.VisualStateGroups>
        </Grid>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="ToolButtonStyle" TargetType="Button" BasedOn="{StaticResource IOSButtonStyle}">
      <Setter Property="MinHeight" Value="30"/><Setter Property="Padding" Value="12,5"/>
      <Setter Property="FontSize" Value="12"/><Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}"/>
    </Style>
    <Style x:Key="DarkComboItemStyle" TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}"/><Setter Property="Background" Value="{DynamicResource ControlBrush}"/>
      <Setter Property="Padding" Value="10,6"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem"><Border x:Name="ItemRoot" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter TargetName="ItemRoot" Property="Background" Value="{DynamicResource ControlHoverBrush}"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter TargetName="ItemRoot" Property="Background" Value="{DynamicResource SelectedBrush}"/><Setter Property="Foreground" Value="{DynamicResource PrimaryTextBrush}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="DarkComboStyle" TargetType="ComboBox">
      <Setter Property="Foreground" Value="{DynamicResource PrimaryTextBrush}"/><Setter Property="Background" Value="{DynamicResource ControlBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource SeparatorBrush}"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,5"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox"><Grid><Border x:Name="ComboRoot" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="7" Padding="{TemplateBinding Padding}"><Grid><ContentPresenter x:Name="SelectionContent" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" VerticalAlignment="Center" HorizontalAlignment="Left"/><Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,2,0" Fill="{DynamicResource MutedTextBrush}" Data="M 0 0 L 4 4 L 8 0 Z"/></Grid></Border><ToggleButton Focusable="False" IsChecked="{Binding IsDropDownOpen,RelativeSource={RelativeSource TemplatedParent},Mode=TwoWay}" Background="Transparent" BorderThickness="0" Opacity="0"><ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border Background="Transparent"/></ControlTemplate></ToggleButton.Template></ToggleButton><Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False"><Border Background="{DynamicResource ControlBrush}" BorderBrush="{DynamicResource SeparatorBrush}" BorderThickness="1" CornerRadius="7" Margin="0,3,0,0" MinWidth="{Binding ActualWidth,RelativeSource={RelativeSource TemplatedParent}}"><ScrollViewer><ItemsPresenter/></ScrollViewer></Border></Popup></Grid><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ComboRoot" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="ComboRoot" Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="DarkSearchStyle" TargetType="TextBox">
      <Setter Property="Foreground" Value="{DynamicResource PrimaryTextBrush}"/><Setter Property="Background" Value="{DynamicResource ControlBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource SeparatorBrush}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="10,5"/>
    </Style>
    <Style x:Key="DarkCheckStyle" TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox">
        <StackPanel Orientation="Horizontal"><Border x:Name="CheckRoot" Width="16" Height="16" CornerRadius="4" Background="{DynamicResource ControlBrush}" BorderBrush="{DynamicResource SeparatorBrush}" BorderThickness="1" Margin="0,0,7,0"><Path x:Name="CheckMark" Data="M 3 8 L 6.5 11.5 L 13 4.5" Stroke="{DynamicResource AccentBrush}" StrokeThickness="2" Visibility="Collapsed"/></Border><ContentPresenter VerticalAlignment="Center"/></StackPanel>
        <ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="CheckRoot" Property="Background" Value="#26394B"/><Setter TargetName="CheckRoot" Property="BorderBrush" Value="#7892A8"/><Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/></Trigger><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="CheckRoot" Property="BorderBrush" Value="#819AAF"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="LogHeaderStyle" TargetType="GridViewColumnHeader">
      <Setter Property="Foreground" Value="{DynamicResource MutedTextBrush}"/><Setter Property="Background" Value="{DynamicResource PanelBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource SeparatorBrush}"/><Setter Property="BorderThickness" Value="0,0,1,1"/>
      <Setter Property="Padding" Value="10,7"/><Setter Property="FontSize" Value="11"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="GridViewColumnHeader">
        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}"><ContentPresenter VerticalAlignment="Center"/></Border>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="LogItemStyle" TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}"/><Setter Property="Background" Value="{DynamicResource LogBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource SeparatorBrush}"/><Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="Padding" Value="4,4"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border x:Name="ItemRoot" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Stretch"/></Border><ControlTemplate.Triggers><Trigger Property="ItemsControl.AlternationIndex" Value="1"><Setter TargetName="ItemRoot" Property="Background" Value="{DynamicResource LogAlternateBrush}"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter TargetName="ItemRoot" Property="Background" Value="{DynamicResource SelectedBrush}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Grid x:Name="PageRoot" Margin="28">
    <Grid x:Name="BackdropRoot">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="20"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="24"/><RowDefinition Height="Auto"/><RowDefinition Height="16"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="16"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="16"/><RowDefinition Height="Auto"/><RowDefinition Height="18"/>
      <RowDefinition Height="*"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Grid Grid.Row="0">
      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="DISPLAY MODE" Foreground="{DynamicResource AccentBrush}" FontSize="13" FontWeight="Bold"/>
        <TextBlock Text="显示模式控制台" FontSize="33" FontWeight="SemiBold" Margin="0,6,0,0"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
        <Border x:Name="StatusPill" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource IOSBorder}" BorderThickness="1" CornerRadius="20" Padding="17,10">
          <StackPanel Orientation="Horizontal">
            <Ellipse x:Name="StatusDot" Width="10" Height="10" Fill="{DynamicResource SuccessBrush}" Margin="0,0,9,0"/>
            <TextBlock x:Name="StatusText" Text="正在检测" FontSize="14" VerticalAlignment="Center"/>
          </StackPanel>
        </Border>
        <Button x:Name="ThemeButton" Style="{StaticResource ToolButtonStyle}" Width="40" Height="40" MinHeight="40" Padding="0" Margin="10,0,0,0" ToolTip="更换主题">
          <TextBlock Text="◐" FontSize="20" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Button>
      </StackPanel>
    </Grid>
    <Border x:Name="ThemeFlyout" Grid.Row="0" Grid.RowSpan="14" HorizontalAlignment="Right" VerticalAlignment="Top" Width="250" Margin="0,50,0,0" Padding="12" Panel.ZIndex="900" Visibility="Collapsed" Opacity="0" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource IOSBorder}" BorderThickness="1" CornerRadius="16">
      <StackPanel>
        <TextBlock Text="界面主题" FontSize="14" FontWeight="SemiBold" Margin="7,3,7,10"/>
        <Button x:Name="ThemeSystemButton" Style="{StaticResource ToolButtonStyle}" Content="跟随系统" Margin="0,0,0,6"/>
        <Button x:Name="ThemeDarkButton" Style="{StaticResource ToolButtonStyle}" Content="深色" Margin="0,0,0,6"/>
        <Button x:Name="ThemeLightButton" Style="{StaticResource ToolButtonStyle}" Content="浅色" Margin="0,0,0,6"/>
        <Button x:Name="ThemePinkButton" Style="{StaticResource ToolButtonStyle}" Content="渐变粉"/>
      </StackPanel>
    </Border>
    <Border x:Name="DisplayCard" Grid.Row="2" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource IOSBorder}" BorderThickness="1" CornerRadius="18" Padding="26">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock Text="当前 NVIDIA 显示器" Foreground="{DynamicResource MutedTextBrush}" FontSize="13"/>
          <TextBlock x:Name="MonitorName" Text="正在读取设备信息…" FontSize="20" FontWeight="SemiBold" Margin="0,8,0,0"/>
          <TextBlock x:Name="AdapterName" Text="" Foreground="{DynamicResource SecondaryTextBrush}" FontSize="13" Margin="0,8,0,0"/>
        </StackPanel>
        <StackPanel Grid.Column="1" HorizontalAlignment="Right">
          <TextBlock Text="当前分辨率" Foreground="{DynamicResource MutedTextBrush}" FontSize="13" HorizontalAlignment="Right"/>
          <TextBlock x:Name="ResolutionText" Text="—" FontSize="27" FontWeight="SemiBold" Margin="0,6,0,0" HorizontalAlignment="Right"/>
          <TextBlock x:Name="RefreshText" Text="" Foreground="{DynamicResource SecondaryTextBrush}" FontSize="13" HorizontalAlignment="Right"/>
        </StackPanel>
      </Grid>
    </Border>
    <Grid Grid.Row="4">
      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="18"/><ColumnDefinition/></Grid.ColumnDefinitions>
      <Button x:Name="NativeButton" Grid.Column="0" Style="{StaticResource IOSButtonStyle}">
        <StackPanel><TextBlock x:Name="NativeTitle" Text="原始模式" FontSize="19" HorizontalAlignment="Center"/><TextBlock x:Name="NativeModeText" Text="1920 × 1080 · 永久基线" FontSize="13" Foreground="{DynamicResource SecondaryTextBrush}" Margin="0,7,0,0" HorizontalAlignment="Center"/></StackPanel>
      </Button>
      <Button x:Name="ApplyButton" Grid.Column="2" Style="{StaticResource IOSButtonStyle}">
        <StackPanel><TextBlock x:Name="Mode1280Title" Text="1280 × 880" FontSize="19" HorizontalAlignment="Center"/><TextBlock Text="单纯修改分辨率" FontSize="13" Foreground="{DynamicResource SecondaryTextBrush}" Margin="0,7,0,0" HorizontalAlignment="Center"/></StackPanel>
      </Button>
    </Grid>
    <Grid Grid.Row="6">
      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="18"/><ColumnDefinition/></Grid.ColumnDefinitions>
      <Button x:Name="Set1440Button" Grid.Column="0" Style="{StaticResource IOSButtonStyle}">
        <StackPanel><TextBlock x:Name="Mode1440Title" Text="1440 × 1080" FontSize="19" HorizontalAlignment="Center"/><TextBlock Text="单纯修改分辨率 · 4:3 模式" FontSize="13" Foreground="{DynamicResource SecondaryTextBrush}" Margin="0,7,0,0" HorizontalAlignment="Center"/></StackPanel>
      </Button>
      <Button x:Name="Set1920Button" Grid.Column="2" Style="{StaticResource IOSButtonStyle}" ToolTip="2K 4:3 分辨率，1K 屏禁止使用哦">
        <StackPanel><TextBlock x:Name="Mode1920Title" Text="1920 × 1440" FontSize="19" HorizontalAlignment="Center"/><TextBlock x:Name="Set1920Hint" Text="2K 4:3 分辨率，1K 屏禁止使用哦" FontSize="13" Foreground="{DynamicResource WarningBrush}" Margin="0,7,0,0" HorizontalAlignment="Center"/></StackPanel>
      </Button>
    </Grid>
    <Grid Grid.Row="8">
      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="18"/><ColumnDefinition/></Grid.ColumnDefinitions>
      <Button x:Name="DeviceButton" Grid.Column="0" Style="{StaticResource IOSButtonStyle}" Content="禁用此 Monitor 设备"/>
      <Button x:Name="RestoreButton" Grid.Column="2" Style="{StaticResource IOSButtonStyle}" Content="一键复原：启用并恢复最初模式"/>
    </Grid>
    <TextBlock x:Name="BaselineText" Grid.Row="10" Text="最初模式：正在读取…" Foreground="{DynamicResource MutedTextBrush}" FontSize="13"/>
    <Border x:Name="LogPanel" Grid.Row="12" Background="{DynamicResource LogBrush}" BorderBrush="{DynamicResource SeparatorBrush}" BorderThickness="1" CornerRadius="14" MinHeight="230">
      <Grid x:Name="LogBody">
        <Grid.RowDefinitions><RowDefinition Height="46"/><RowDefinition Height="1"/><RowDefinition Height="42"/><RowDefinition Height="1"/><RowDefinition Height="*"/><RowDefinition Height="32"/></Grid.RowDefinitions>
        <Border x:Name="LogHeader" Grid.Row="0" Background="{DynamicResource PanelBrush}" CornerRadius="13,13,0,0" Padding="15,0">
          <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center"><Ellipse x:Name="LogStatusDot" Width="9" Height="9" Fill="#55D69E" Margin="0,0,9,0"/><TextBlock Text="详细运行日志" FontSize="15" FontWeight="SemiBold"/><TextBlock x:Name="ProgressText" Text="  ·  准备就绪" Foreground="#8C9AAA" FontSize="12" VerticalAlignment="Center"/></StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><Border Background="#17222E" CornerRadius="9" Padding="8,3" Margin="0,0,6,0"><TextBlock x:Name="InfoCountText" Text="信息 0" Foreground="#A9C6E6" FontSize="11"/></Border><Border Background="#2A2519" CornerRadius="9" Padding="8,3" Margin="0,0,6,0"><TextBlock x:Name="WarnCountText" Text="警告 0" Foreground="#E3B55B" FontSize="11"/></Border><Border Background="#2A1B20" CornerRadius="9" Padding="8,3" Margin="0,0,10,0"><TextBlock x:Name="ErrorCountText" Text="错误 0" Foreground="#E06B76" FontSize="11"/></Border><Button x:Name="LogToggle" Style="{StaticResource ToolButtonStyle}" Content="收起日志"/></StackPanel>
          </Grid>
        </Border>
        <Border Grid.Row="1" Background="{DynamicResource SeparatorBrush}"/>
        <Border x:Name="LogToolbar" Grid.Row="2" Background="{DynamicResource PanelBrush}" Padding="12,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="125"/><ColumnDefinition Width="10"/><ColumnDefinition/><ColumnDefinition Width="10"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <ComboBox x:Name="LogLevelFilter" Style="{StaticResource DarkComboStyle}" SelectedIndex="0"><ComboBoxItem Style="{StaticResource DarkComboItemStyle}" Content="全部级别"/><ComboBoxItem Style="{StaticResource DarkComboItemStyle}" Content="信息"/><ComboBoxItem Style="{StaticResource DarkComboItemStyle}" Content="成功"/><ComboBoxItem Style="{StaticResource DarkComboItemStyle}" Content="警告"/><ComboBoxItem Style="{StaticResource DarkComboItemStyle}" Content="错误"/></ComboBox>
          <TextBox x:Name="LogSearchBox" Grid.Column="2" Style="{StaticResource DarkSearchStyle}" ToolTip="搜索消息或来源"/>
          <StackPanel Grid.Column="4" Orientation="Horizontal"><CheckBox x:Name="AutoScrollToggle" Style="{StaticResource DarkCheckStyle}" Content="自动滚动" IsChecked="True" VerticalAlignment="Center" Margin="0,0,10,0"/><Button x:Name="CopyLogButton" Style="{StaticResource ToolButtonStyle}" Content="复制全部" Margin="0,0,7,0"/><Button x:Name="ClearLogButton" Style="{StaticResource ToolButtonStyle}" Content="清空"/></StackPanel>
        </Grid></Border>
        <Border x:Name="LogDivider" Grid.Row="3" Background="{DynamicResource SeparatorBrush}"/>
        <ListBox x:Name="LogBox" Grid.Row="4" Background="{DynamicResource LogBrush}" Foreground="{DynamicResource SecondaryTextBrush}" BorderThickness="0" AlternationCount="2" ItemContainerStyle="{StaticResource LogItemStyle}" ScrollViewer.HorizontalScrollBarVisibility="Disabled" VirtualizingPanel.IsVirtualizing="True" VirtualizingPanel.VirtualizationMode="Recycling">
          <ListBox.ItemTemplate><DataTemplate><Grid Margin="8,3"><Grid.ColumnDefinitions><ColumnDefinition Width="82"/><ColumnDefinition Width="66"/><ColumnDefinition Width="76"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="{Binding Timestamp}" Foreground="{DynamicResource MutedTextBrush}" FontSize="12" VerticalAlignment="Center"/><Border Grid.Column="1" Background="{Binding BadgeBrush}" CornerRadius="8" Padding="7,2" HorizontalAlignment="Left" VerticalAlignment="Center"><TextBlock Text="{Binding Level}" Foreground="{Binding LevelBrush}" FontSize="12"/></Border><TextBlock Grid.Column="2" Text="{Binding Source}" Foreground="{DynamicResource MutedTextBrush}" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="3" Text="{Binding Message}" TextWrapping="Wrap" Foreground="{DynamicResource SecondaryTextBrush}" FontSize="13" VerticalAlignment="Center"/></Grid></DataTemplate></ListBox.ItemTemplate>
        </ListBox>
        <Border x:Name="LogFooter" Grid.Row="5" Background="{DynamicResource PanelBrush}" CornerRadius="0,0,13,13" Padding="13,0"><Grid><TextBlock x:Name="LogEntryCountText" Text="0 条记录" Foreground="{DynamicResource MutedTextBrush}" FontSize="12" VerticalAlignment="Center"/><TextBlock x:Name="LogFilterStatusText" Text="显示全部记录" Foreground="{DynamicResource MutedTextBrush}" FontSize="12" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid></Border>
      </Grid>
    </Border>
    </Grid>
    <Grid x:Name="GlassOverlay" Panel.ZIndex="1000" IsHitTestVisible="False" ClipToBounds="False"/>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)
$workArea = [Windows.SystemParameters]::WorkArea
$Window.Width = [Math]::Min(1100, [Math]::Max(900, $workArea.Width - 24))
$Window.Height = [Math]::Min(850, [Math]::Max(680, $workArea.Height - 24))
$Window.MinWidth = [Math]::Min(920, $Window.Width)
$Window.MinHeight = [Math]::Min(700, $Window.Height)
$names = 'PageRoot','BackdropRoot','GlassOverlay','ThemeFlyout','StatusPill','StatusDot','StatusText','MonitorName','AdapterName','ResolutionText','RefreshText',
    'ThemeButton','ThemeSystemButton','ThemeDarkButton','ThemeLightButton','ThemePinkButton',
    'NativeButton','NativeModeText','Mode1280Title','ApplyButton','Mode1440Title','Set1440Button',
    'Mode1920Title','Set1920Button','Set1920Hint','DeviceButton','RestoreButton','BaselineText',
    'LogPanel','LogBody','LogStatusDot','ProgressText','InfoCountText','WarnCountText','ErrorCountText',
    'LogToolbar','LogDivider','LogFooter','LogLevelFilter','LogSearchBox','AutoScrollToggle',
    'CopyLogButton','ClearLogButton','LogBox','LogEntryCountText','LogFilterStatusText','LogToggle'
foreach ($name in $names) { Set-Variable -Name $name -Value $Window.FindName($name) }
$script:GlassLayer = New-Object MonitorModeGlass.LiquidGlassLayer
$script:GlassLayer.SetBackdrop($BackdropRoot)
$script:GlassLayer.HorizontalAlignment = 'Stretch'
$script:GlassLayer.VerticalAlignment = 'Stretch'
$GlassOverlay.Children.Add($script:GlassLayer) | Out-Null
$script:GlassController = New-Object MonitorModeGlass.LiquidGlassController -ArgumentList $Window, $PageRoot, $script:GlassLayer

$iconPath = Join-Path $PSScriptRoot 'MonitorModeConsole.ico'
if (Test-Path -LiteralPath $iconPath) {
    try {
        $iconStream = [IO.File]::OpenRead($iconPath)
        $iconDecoder = New-Object Windows.Media.Imaging.IconBitmapDecoder(
            $iconStream,
            [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
            [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        )
        $Window.Icon = $iconDecoder.Frames | Sort-Object PixelWidth | Select-Object -Last 1
        $iconStream.Dispose()
    } catch { }
}

$SettingsRoot = if ($TestMode) { Join-Path ([IO.Path]::GetTempPath()) 'MonitorModeConsole-Test' } else { Join-Path $env:LOCALAPPDATA 'MonitorModeConsole' }
$SettingsPath = Join-Path $SettingsRoot 'ui-settings.json'
$CrashLogPath = Join-Path $SettingsRoot 'crash.log'
$script:ThemeMode = 'System'
$script:EffectiveTheme = ''

function Write-CrashReport([string]$Context, [System.Exception]$Exception) {
    try {
        [IO.Directory]::CreateDirectory($SettingsRoot) | Out-Null
        $details = @(
            ('[{0}] {1}' -f (Get-Date).ToString('o'), $Context)
            ($Exception.ToString())
            ''
        ) -join [Environment]::NewLine
        [IO.File]::AppendAllText($CrashLogPath, $details, (New-Object Text.UTF8Encoding $false))
    } catch { }
}

function Get-SystemTheme {
    try {
        $value = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme
        if ([int]$value -eq 0) { return 'Dark' }
    } catch { }
    return 'Light'
}

function Read-UiSettings {
    foreach ($path in @($SettingsPath, "$SettingsPath.bak")) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $settings = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            if ([string]$settings.ThemeMode -in @('Light','Dark','System','Pink')) {
                $script:ThemeMode = [string]$settings.ThemeMode
                return
            }
        } catch { }
    }
}

function Save-UiSettings {
    $temporary = "$SettingsPath.tmp"
    try {
        [IO.Directory]::CreateDirectory($SettingsRoot) | Out-Null
        $json = [pscustomobject]@{
            Version = 1
            ThemeMode = $script:ThemeMode
            SavedAt = (Get-Date).ToString('o')
        } | ConvertTo-Json
        [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding $false))
        if ([IO.File]::Exists($SettingsPath)) {
            [IO.File]::Replace($temporary, $SettingsPath, "$SettingsPath.bak", $true)
        } else {
            [IO.File]::Move($temporary, $SettingsPath)
        }
        return $true
    } catch {
        Write-CrashReport '保存界面设置失败' $_.Exception
        return $false
    } finally {
        try { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } } catch { }
    }
}

function New-ThemeBrush([string]$Color) {
    return New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Color))
}

function New-ThemeGradient([string]$Start, [string]$End) {
    $brush = New-Object Windows.Media.LinearGradientBrush
    $brush.StartPoint = New-Object Windows.Point -ArgumentList 0, 0
    $brush.EndPoint = New-Object Windows.Point -ArgumentList 1, 1
    [void]$brush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($Start), 0)))
    [void]$brush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($End), 1)))
    return $brush
}

function Set-ThemeResource([string]$Key, $Brush) {
    if ($Window.Resources.Contains($Key)) { $Window.Resources.Remove($Key) }
    $Window.Resources.Add($Key, $Brush)
}

function Apply-Theme([string]$Mode, [switch]$Persist) {
    if ($Mode -notin @('Light','Dark','System','Pink')) { $Mode = 'System' }
    $script:ThemeMode = $Mode
    $effective = if ($Mode -eq 'System') { Get-SystemTheme } else { $Mode }
    $script:EffectiveTheme = $effective
    if ($effective -eq 'Light') {
        $colors = @('#FFF8FB','#EAF0F7','#FFFFFF','#EEF3F9','#18212F','#607083','#7B8999','#D5DEE8','#F5F8FC','#E8EFF6','#DDE7F1','#4F7CFF')
    } elseif ($effective -eq 'Pink') {
        $colors = @('#FFF5FA','#F1ECFF','#FFF0F6','#EFE8FF','#342A36','#756779','#8B7B90','#E7D7E5','#FFF7FB','#F1E9F8','#E9DDEA','#D85C93')
    } else {
        $colors = @('#090A0D','#121827','#24262C','#171B22','#F5F5F7','#AEB9C6','#748394','#28FFFFFF','#101520','#111923','#0B1016','#64B5F6')
    }
    Set-ThemeResource 'WindowBackgroundBrush' (New-ThemeGradient $colors[0] $colors[1])
    Set-ThemeResource 'IOSSurface' (New-ThemeGradient $colors[2] $colors[3])
    Set-ThemeResource 'PrimaryTextBrush' (New-ThemeBrush $colors[4])
    Set-ThemeResource 'SecondaryTextBrush' (New-ThemeBrush $colors[5])
    Set-ThemeResource 'MutedTextBrush' (New-ThemeBrush $colors[6])
    Set-ThemeResource 'IOSBorder' (New-ThemeBrush $colors[7])
    Set-ThemeResource 'CardBrush' (New-ThemeBrush $colors[8])
    Set-ThemeResource 'PanelBrush' (New-ThemeBrush $colors[8])
    Set-ThemeResource 'ControlBrush' (New-ThemeBrush $colors[9])
    Set-ThemeResource 'LogBrush' (New-ThemeBrush $colors[9])
    Set-ThemeResource 'LogAlternateBrush' (New-ThemeBrush $colors[10])
    Set-ThemeResource 'SelectedBrush' (New-ThemeBrush $colors[10])
    Set-ThemeResource 'SeparatorBrush' (New-ThemeBrush $colors[7])
    Set-ThemeResource 'ControlHoverBrush' (New-ThemeBrush $colors[10])
    Set-ThemeResource 'AccentBrush' (New-ThemeBrush $colors[11])
    $ThemeButton.ToolTip = '更换主题 · ' + @{ Light='浅色'; Dark='深色'; System='跟随系统'; Pink='渐变粉' }[$Mode]
    if ($script:GlassController) { $script:GlassController.SetTheme($effective) }
    if ($Persist -and -not (Save-UiSettings)) {
        if (Get-Command Add-Log -ErrorAction SilentlyContinue) {
            Add-Log ('主题已应用，但偏好未能保存。诊断信息：' + $CrashLogPath) '警告' 'THEME'
        }
        $ProgressText.Text = '  ·  主题已应用，但保存偏好失败。'
    }
}

function Select-Theme([string]$Mode) {
    try {
        Apply-Theme $Mode -Persist
    } catch {
        Write-CrashReport ('应用主题失败：' + $Mode) $_.Exception
        if (Get-Command Add-Log -ErrorAction SilentlyContinue) { Add-Log $_.Exception.Message '错误' 'THEME' }
        $ProgressText.Text = '  ·  主题切换失败：' + $_.Exception.Message
    } finally {
        Hide-ThemeFlyout
    }
}

function Hide-ThemeFlyout {
    $ThemeFlyout.Visibility = 'Collapsed'
    $ThemeFlyout.Opacity = 0
}

function Show-ThemeFlyout {
    $ThemeFlyout.Visibility = 'Visible'
    $ThemeFlyout.Opacity = 1
}

Read-UiSettings
Apply-Theme $script:ThemeMode

[void]$LogLevelFilter.ApplyTemplate()
$LogLevelFilter.IsDropDownOpen = $true
[void]$Window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)
$LogLevelFilter.IsDropDownOpen = $false

$script:Busy = $false
$script:CurrentStatus = $null
$script:PendingAction = $null
$script:AsyncPowerShell = $null
$script:AsyncHandle = $null
$script:StatusPowerShell = $null
$script:StatusHandle = $null
$script:LogEntries = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
$script:LogView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($script:LogEntries)
$LogBox.ItemsSource = $script:LogView

function Get-LogColors([string]$Level) {
    switch ($Level) {
        '成功' { return @('#6FE0AD', '#1E3A31') }
        '警告' { return @('#E3B55B', '#3A301D') }
        '错误' { return @('#E77A85', '#3B2027') }
        default { return @('#A9C6E6', '#1A2A38') }
    }
}

function Update-LogSummary {
    $all = @($script:LogEntries)
    $InfoCountText.Text = '信息 {0}' -f @($all | Where-Object { $_.Level -in @('信息','成功') }).Count
    $WarnCountText.Text = '警告 {0}' -f @($all | Where-Object { $_.Level -eq '警告' }).Count
    $ErrorCountText.Text = '错误 {0}' -f @($all | Where-Object { $_.Level -eq '错误' }).Count
    $LogEntryCountText.Text = '{0} 条记录' -f $all.Count
    $visible = @($script:LogView).Count
    $LogFilterStatusText.Text = if ($visible -eq $all.Count) { '显示全部记录' } else { '显示 {0} / {1}' -f $visible, $all.Count }
}

function Refresh-LogFilter {
    $selected = [string](($LogLevelFilter.SelectedItem).Content)
    $query = $LogSearchBox.Text.Trim()
    $script:LogView.Filter = {
        param($entry)
        $levelOk = $selected -eq '全部级别' -or $entry.Level -eq $selected
        $searchOk = [string]::IsNullOrWhiteSpace($query) -or $entry.Message.IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or $entry.Source.IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -ge 0
        return $levelOk -and $searchOk
    }.GetNewClosure()
    $script:LogView.Refresh()
    Update-LogSummary
}

function Add-Log {
    param([string]$Text, [ValidateSet('信息','成功','警告','错误')][string]$Level = '信息', [string]$Source = 'UI')
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    foreach ($line in ($Text -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $colors = Get-LogColors $Level
        $entry = [pscustomobject]@{
            Timestamp = (Get-Date -Format 'HH:mm:ss')
            Level = $Level
            Source = $Source
            Message = $line.Trim()
            LevelBrush = $colors[0]
            BadgeBrush = $colors[1]
        }
        $script:LogEntries.Add($entry)
        while ($script:LogEntries.Count -gt 1500) { $script:LogEntries.RemoveAt(0) }
        if ($AutoScrollToggle.IsChecked -eq $true) { $LogBox.ScrollIntoView($entry) }
    }
    Refresh-LogFilter
}

function Set-Busy([bool]$Value, [string]$Message = '') {
    $script:Busy = $Value
    $NativeButton.IsEnabled = -not $Value
    $ApplyButton.IsEnabled = -not $Value
    $Set1440Button.IsEnabled = -not $Value
    $Set1920Button.IsEnabled = -not $Value
    $DeviceButton.IsEnabled = -not $Value
    $RestoreButton.IsEnabled = -not $Value
    if ($Message) { $ProgressText.Text = '  ·  ' + $Message }
    if ($Value) {
        $StatusText.Text = '正在处理'
        $StatusDot.Fill = '#F5B94C'
        $LogStatusDot.Fill = '#E3B55B'
    }
}

function Invoke-Core([string]$Action, [string]$InstanceId = '') {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $CoreScript), '-Action', $Action, '-NonInteractive')
    if ($InstanceId) { $arguments += @('-TargetInstanceId', ('"{0}"' -f $InstanceId)) }
    if ($Action -eq 'Disable') { $arguments += '-AllowSoleDisplayDisable' }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $startInfo.Arguments = $arguments -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdout.Trim(); Error = $stderr.Trim() }
}

function Get-CoreStatus {
    $result = Invoke-Core -Action 'Status'
    if ($result.ExitCode -ne 0) { throw ($result.Error + ' ' + $result.Output).Trim() }
    $jsonLine = ($result.Output -split "`r?`n" | Where-Object { $_ -match '^\{' } | Select-Object -Last 1)
    if (-not $jsonLine) { throw '无法读取显示器状态。' }
    return $jsonLine | ConvertFrom-Json
}

function Apply-StatusResult($status) {
        $script:CurrentStatus = $status
        $savedState = $status.SavedState
        $display = $null
        if ($savedState) {
            $display = @($status.NvidiaDisplays) | Where-Object { $_.InstanceId -eq $savedState.InstanceId } | Select-Object -First 1
        }
        if (-not $display -and -not $savedState) { $display = @($status.NvidiaDisplays) | Select-Object -First 1 }
        $baseline = if ($savedState) { $savedState.Baseline } else { $null }

        $Mode1280Title.Text = '1280 × 880'
        $Mode1440Title.Text = '1440 × 1080'
        $Mode1920Title.Text = '1920 × 1440'
        if ($baseline) {
            $NativeModeText.Text = ('{0} × {1} @ {2}Hz · 永久基线' -f $baseline.Width, $baseline.Height, $baseline.Frequency)
            $BaselineText.Text = ('最初模式：{0} × {1} @ {2}Hz' -f $baseline.Width, $baseline.Height, $baseline.Frequency)
        } else {
            $NativeModeText.Text = '首次切换时保存当前模式'
            $BaselineText.Text = '最初模式：尚未记录'
        }

        if ($display -and [bool]$display.PnpDisabled -and -not $savedState) {
            $MonitorName.Text = $display.MonitorName
            $AdapterName.Text = $display.AdapterName
            $ResolutionText.Text = '已禁用'
            $RefreshText.Text = 'Code 22 · 缺少匹配的 v6 快照'
            foreach ($button in @($NativeButton,$ApplyButton,$Set1440Button,$Set1920Button,$DeviceButton)) { $button.IsEnabled = $false }
            $StatusText.Text = '设备已禁用'
            $StatusDot.Fill = '#F5B94C'
        } elseif ($status.TargetPnpDisabled -and $savedState) {
            $MonitorName.Text = $savedState.MonitorName
            $AdapterName.Text = $savedState.AdapterName
            $ResolutionText.Text = '已禁用'
            $writeAvailable = [bool]$status.DisabledModeWriteAvailable
            $RefreshText.Text = if ($status.DisabledModeWriteKind -eq 'ImmediateResidualPath') { 'Code 22 · 可直接写入并验证当前模式' } elseif ($writeAvailable) { 'Code 22 · 仅写入 Windows 持久模式' } else { 'Code 22 · 缺少禁用前显示路由快照' }
            $NativeButton.IsEnabled = -not $script:Busy -and $writeAvailable
            $ApplyButton.IsEnabled = -not $script:Busy -and $writeAvailable -and [bool]$savedState.Supports1280
            $Set1440Button.IsEnabled = -not $script:Busy -and $writeAvailable -and [bool]$savedState.Supports1440
            $Set1920Button.IsEnabled = -not $script:Busy -and $writeAvailable -and [bool]$savedState.Allows1920
            if ([bool]$savedState.Allows1920) {
                $Set1920Hint.Text = '2K 4:3 分辨率 · 全程保持 Code 22'
                $Set1920Button.ToolTip = if ($status.DisabledModeWriteKind -eq 'ImmediateResidualPath') { '直接写入残留显示路径，设备保持禁用' } else { '只写入 Windows 持久模式，设备保持禁用' }
            } else {
                $Set1920Hint.Text = '2K 4:3 分辨率，1K 屏禁止使用哦'
                $Set1920Button.ToolTip = '保存的显示器不是原生 2K 屏，或驱动没有此模式，已禁止使用'
            }
            $DeviceButton.IsEnabled = -not $script:Busy
            $DeviceButton.Content = '启用显示器'
            $StatusText.Text = '设备已禁用'
            $StatusDot.Fill = '#F5B94C'
        } elseif ($display) {
            $MonitorName.Text = $display.MonitorName
            $AdapterName.Text = $display.AdapterName
            $ResolutionText.Text = ('{0} × {1}' -f $display.CurrentWidth, $display.CurrentHeight)
            $RefreshText.Text = ('{0} Hz  ·  {1}' -f $display.CurrentFrequency, $display.DeviceName)
            $NativeButton.IsEnabled = -not $script:Busy
            $ApplyButton.IsEnabled = -not $script:Busy -and [bool]$display.Supports1280
            $Set1440Button.IsEnabled = -not $script:Busy -and [bool]$display.Supports1440
            $Set1920Button.IsEnabled = -not $script:Busy -and [bool]$display.Allows1920
            $DeviceButton.IsEnabled = -not $script:Busy
            $DeviceButton.Content = '禁用此 Monitor 设备'

            if ($baseline -and $display.CurrentWidth -eq $baseline.Width -and $display.CurrentHeight -eq $baseline.Height) { $NativeModeText.Text += ' · 当前' }
            if ($display.CurrentWidth -eq 1280 -and $display.CurrentHeight -eq 880) { $Mode1280Title.Text += ' · 当前' }
            if ($display.CurrentWidth -eq 1440 -and $display.CurrentHeight -eq 1080) { $Mode1440Title.Text += ' · 当前' }
            if ($display.CurrentWidth -eq 1920 -and $display.CurrentHeight -eq 1440) { $Mode1920Title.Text += ' · 当前' }

            if ($display.Allows1920) {
                $Set1920Hint.Text = '2K 4:3 分辨率 · 当前显示器支持'
                $Set1920Button.ToolTip = '1920 × 1440 现有模式可用'
            } else {
                $Set1920Hint.Text = '2K 4:3 分辨率，1K 屏禁止使用哦'
                $Set1920Button.ToolTip = '当前显示器不是原生 2K 屏，或驱动没有此模式，已禁止使用'
            }
            $StatusText.Text = '显示器已启用'
            $StatusDot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, 'SuccessBrush')
        } else {
            $MonitorName.Text = '未检测到活动 NVIDIA 显示器'
            $AdapterName.Text = ''
            $ResolutionText.Text = '—'
            $RefreshText.Text = ''
            $NativeButton.IsEnabled = $false
            $ApplyButton.IsEnabled = $false
            $Set1440Button.IsEnabled = $false
            $Set1920Button.IsEnabled = $false
            $DeviceButton.IsEnabled = $false
            $StatusText.Text = '未检测到设备'
            $StatusDot.Fill = '#F05D72'
        }

        $RestoreButton.IsEnabled = -not $script:Busy -and [bool]$status.RestoreAvailable
        if ($status.TargetPnpDisabled) {
            if ($status.DisabledModeWriteKind -eq 'ImmediateResidualPath') {
                $ProgressText.Text = '显示器保持 Code 22；分辨率将直接写入残留活动路径并即时验证。'
            } elseif ($status.DisabledModeWriteKind -eq 'PersistentRegistry') {
                $ProgressText.Text = '显示器保持 Code 22；分辨率只写入 Windows 持久模式，不启用设备，也不使用程序队列。'
            } else {
                $ProgressText.Text = '旧状态缺少禁用前显示路由快照；需手动启用后重新禁用一次，才能安全离线写入。'
            }
        } elseif ($status.TargetMissing) {
            $ProgressText.Text = '  ·  保存的显示器当前缺失，无法切换分辨率或启用。'
        } elseif ($status.TargetError) {
            $ProgressText.Text = '  ·  显示器存在设备错误，未按“已禁用”处理。'
        } else {
            $ProgressText.Text = '分辨率按钮只修改分辨率；设备启用状态由独立按钮控制。'
        }
}

function Set-StatusError([string]$Message) {
        $script:CurrentStatus = $null
        foreach ($button in @($NativeButton,$ApplyButton,$Set1440Button,$Set1920Button,$DeviceButton,$RestoreButton)) { $button.IsEnabled = $false }
        $StatusText.Text = '检测失败'
        $StatusDot.Fill = '#F05D72'
        $ProgressText.Text = '  ·  ' + $Message
        $LogStatusDot.Fill = '#E06B76'
        Add-Log $Message '错误' 'STATUS'
}

function New-TestStatus {
    return [pscustomobject]@{
        NvidiaDisplays = @([pscustomobject]@{
            MonitorName = '测试显示器'
            AdapterName = '隔离测试模式 · 不执行真实显示器操作'
            CurrentWidth = 1920
            CurrentHeight = 1080
            CurrentFrequency = 240
            DeviceName = '\\.\DISPLAY1'
            InstanceId = 'TEST\MONITOR'
            Supports1280 = $true
            Supports1440 = $true
            Allows1920 = $true
        })
        SavedState = $null
        TargetPnpDisabled = $false
        TargetMissing = $false
        TargetError = $false
        DeviceDisabled = $false
        RestoreAvailable = $false
        ActiveDisplayCount = 1
    }
}

function Start-StatusRefresh {
    if ($script:StatusHandle -or $script:Busy) { return }
    foreach ($button in @($NativeButton,$ApplyButton,$Set1440Button,$Set1920Button,$DeviceButton,$RestoreButton)) { $button.IsEnabled = $false }
    $StatusText.Text = '正在检测'
    if ($TestMode) {
        Apply-StatusResult (New-TestStatus)
        return
    }
    $script:StatusPowerShell = [PowerShell]::Create()
    [void]$script:StatusPowerShell.AddScript({ param($ScriptPath) & $ScriptPath -Action Status -NonInteractive }).AddArgument($CoreScript)
    $script:StatusHandle = $script:StatusPowerShell.BeginInvoke()
    $script:PollTimer.Start()
}

function Start-StatusRefreshAfterOperation {
    $script:Busy = $false
    Start-StatusRefresh
}

function Run-Operation([string]$Action, [string]$Message) {
    if ($script:Busy) { return }
    if ($TestMode) {
        Add-Log '隔离测试模式已阻止真实显示器操作。' '警告' 'TEST'
        return
    }
    $savedState = if ($script:CurrentStatus) { $script:CurrentStatus.SavedState } else { $null }
    $display = $null
    if ($script:CurrentStatus -and $savedState) {
        $display = @($script:CurrentStatus.NvidiaDisplays) | Where-Object { $_.InstanceId -eq $savedState.InstanceId } | Select-Object -First 1
    }
    if (-not $display -and $script:CurrentStatus -and -not $savedState) { $display = @($script:CurrentStatus.NvidiaDisplays) | Select-Object -First 1 }
    $modeActions = @('Apply','Set1440','Set1920','SetNative')
    $canSwitchDisabled = $Action -in $modeActions -and $script:CurrentStatus.TargetPnpDisabled -and $savedState
    if ($Action -notin @('Restore', 'Enable') -and -not $display -and -not $canSwitchDisabled) {
        [System.Windows.MessageBox]::Show('当前没有可操作的 NVIDIA 显示器。', '显示模式控制台', 'OK', 'Warning') | Out-Null
        return
    }
    Set-Busy $true $Message
    Add-Log $Message '信息' 'UI'
    $instanceId = if ($savedState) { [string]$savedState.InstanceId } elseif ($display) { [string]$display.InstanceId } else { '' }
    $script:PendingAction = $Action
    $script:AsyncPowerShell = [PowerShell]::Create()
    [void]$script:AsyncPowerShell.AddScript({
        param($ScriptPath, $RequestedAction, $MonitorId)
        $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $ScriptPath),'-Action',$RequestedAction,'-NonInteractive')
        if ($MonitorId) { $arguments += @('-TargetInstanceId',('"{0}"' -f $MonitorId)) }
        if ($RequestedAction -eq 'Disable') { $arguments += '-AllowSoleDisplayDisable' }
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $info.Arguments = $arguments -join ' '
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $info
        [void]$process.Start()
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $out = $outTask.GetAwaiter().GetResult()
        $err = $errTask.GetAwaiter().GetResult()
        [pscustomobject]@{ ExitCode=$process.ExitCode; Output=$out.Trim(); Error=$err.Trim() }
    }).AddArgument($CoreScript).AddArgument($Action).AddArgument($instanceId)
    $script:AsyncHandle = $script:AsyncPowerShell.BeginInvoke()
    $script:PollTimer.Start()
}

$script:PollTimer = New-Object Windows.Threading.DispatcherTimer
$script:PollTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$script:PollTimer.Add_Tick({
    if ($script:StatusHandle -and $script:StatusHandle.IsCompleted) {
        try {
            $output = @($script:StatusPowerShell.EndInvoke($script:StatusHandle))
            $jsonLine = @($output | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^\{' }) | Select-Object -Last 1
            if (-not $jsonLine) { throw '无法读取显示器状态。' }
            Apply-StatusResult ($jsonLine | ConvertFrom-Json)
        } catch {
            Set-StatusError $_.Exception.Message
        } finally {
            if ($script:StatusPowerShell) { $script:StatusPowerShell.Dispose() }
            $script:StatusPowerShell = $null
            $script:StatusHandle = $null
        }
    }
    if ($script:AsyncHandle -and $script:AsyncHandle.IsCompleted) {
        try {
            $result = @($script:AsyncPowerShell.EndInvoke($script:AsyncHandle)) | Select-Object -Last 1
            if ($result.Output) { Add-Log $result.Output $(if ($result.ExitCode -eq 0) { '成功' } else { '信息' }) 'CORE' }
            if ($result.Error) { Add-Log $result.Error '错误' 'STDERR' }
            if ($result.ExitCode -ne 0) { throw (($result.Error + "`n" + $result.Output).Trim()) }
            $modeResult = $null
            foreach ($line in ([string]$result.Output -split "`r?`n")) {
                if ($line -notmatch '^\s*\{') { continue }
                try {
                    $candidate = $line | ConvertFrom-Json
                    if ($candidate.ResultType -eq 'ModeWrite') { $modeResult = $candidate }
                } catch { }
            }
            if ($modeResult -and (-not [bool]$modeResult.Verified -or [int]$modeResult.ProblemCodeAfter -ne 22)) { throw '禁用状态模式写入没有通过 Code 22 验证。' }
            if ($modeResult -and $modeResult.Disposition -eq 'AppliedNow') {
                $ProgressText.Text = '已即时切换并验证；Monitor 设备全程保持 Code 22。'
            } elseif ($modeResult -and $modeResult.Disposition -eq 'PersistedForNextActivation') {
                $ProgressText.Text = '已写入 Windows 持久模式并回读验证；设备全程保持 Code 22，未使用程序队列。'
            } elseif ($script:PendingAction -eq 'Apply') { $ProgressText.Text = '分辨率已切换为 1280 × 880。' }
            elseif ($script:PendingAction -eq 'Set1440') { $ProgressText.Text = '分辨率已切换为 1440 × 1080。' }
            elseif ($script:PendingAction -eq 'Set1920') { $ProgressText.Text = '分辨率已切换为 1920 × 1440。' }
            elseif ($script:PendingAction -eq 'SetNative') { $ProgressText.Text = '已切换到最初分辨率。' }
            elseif ($script:PendingAction -eq 'Disable') { $ProgressText.Text = 'Monitor 设备已禁用。' }
            elseif ($script:PendingAction -eq 'Enable') { $ProgressText.Text = 'Monitor 设备已启用。' }
            else { $ProgressText.Text = '复原成功。显示器与最初分辨率已恢复。' }
        } catch {
            $ProgressText.Text = '  ·  操作失败：' + $_.Exception.Message
            $LogStatusDot.Fill = '#E06B76'
            Add-Log $_.Exception.Message '错误' 'UI'
            [System.Windows.MessageBox]::Show($_.Exception.Message, '操作失败', 'OK', 'Error') | Out-Null
        } finally {
            if ($script:AsyncPowerShell) { $script:AsyncPowerShell.Dispose() }
            $script:AsyncPowerShell = $null
            $script:AsyncHandle = $null
            Start-StatusRefreshAfterOperation
        }
    }
    if (-not $script:AsyncHandle -and -not $script:StatusHandle) { $script:PollTimer.Stop() }
})

$NativeButton.Add_Click({
    Run-Operation 'SetNative' '正在切换到最初分辨率…'
})

$ApplyButton.Add_Click({
    Run-Operation 'Apply' '正在切换到 1280 × 880…'
})

$Set1440Button.Add_Click({
    Run-Operation 'Set1440' '正在切换到 1440 × 1080…'
})

$Set1920Button.Add_Click({
    $disabledNote = if ($script:CurrentStatus -and $script:CurrentStatus.TargetPnpDisabled) {
        if ($script:CurrentStatus.DisabledModeWriteKind -eq 'ImmediateResidualPath') { "`n`n设备会全程保持 Code 22；模式将直接写入残留显示路径。" }
        else { "`n`n设备会全程保持 Code 22；模式只写入 Windows 持久设置，不会启用显示器。" }
    } else { '' }
    $choice = [System.Windows.MessageBox]::Show(
        ("即将切换到 1920 × 1440（2K 4:3）。`n`n仅原生 2K 或更高分辨率的显示器允许使用，是否继续？" + $disabledNote),
        '确认 2K 4:3 分辨率', 'YesNo', 'Warning'
    )
    if ($choice -eq 'Yes') { Run-Operation 'Set1920' '正在切换到 1920 × 1440…' }
})

$DeviceButton.Add_Click({
    if ($null -eq $script:CurrentStatus) { Start-StatusRefresh; return }
    if ($script:CurrentStatus.TargetPnpDisabled) {
        Run-Operation 'Enable' '正在启用 Monitor 设备…'
        return
    }
    $warning = if ($script:CurrentStatus.ActiveDisplayCount -le 1) {
        "这是当前唯一活动显示器。禁用后屏幕会立即消失。`n`n请确认你已准备好通过本程序、第二块屏幕或远程方式重新启用。"
    } else {
        '即将禁用当前 Monitor 设备，桌面布局可能发生变化。是否继续？'
    }
    $choice = [System.Windows.MessageBox]::Show($warning, '确认禁用 Monitor 设备', 'YesNo', 'Warning')
    if ($choice -eq 'Yes') { Run-Operation 'Disable' '正在禁用 Monitor 设备…' }
})

$RestoreButton.Add_Click({
    if ($null -eq $script:CurrentStatus) { Start-StatusRefresh; return }
    if (-not $script:CurrentStatus.RestoreAvailable) {
        [System.Windows.MessageBox]::Show('目前没有可复原的显示模式记录。', '显示模式控制台', 'OK', 'Information') | Out-Null
        return
    }
    Run-Operation 'Restore' '正在重新启用显示器并恢复最初分辨率…'
})

$ThemeButton.Add_Click({
    if ($ThemeFlyout.Visibility -eq 'Visible') { Hide-ThemeFlyout } else { Show-ThemeFlyout }
})
$ThemeSystemButton.Add_Click({ Select-Theme 'System' })
$ThemeDarkButton.Add_Click({ Select-Theme 'Dark' })
$ThemeLightButton.Add_Click({ Select-Theme 'Light' })
$ThemePinkButton.Add_Click({ Select-Theme 'Pink' })
$Window.Add_PreviewMouseDown({
    param($sender, $eventArgs)
    if ($ThemeFlyout.Visibility -ne 'Visible') { return }
    $point = $eventArgs.GetPosition($ThemeFlyout)
    $insideFlyout = $point.X -ge 0 -and $point.Y -ge 0 -and $point.X -le $ThemeFlyout.ActualWidth -and $point.Y -le $ThemeFlyout.ActualHeight
    $themePoint = $eventArgs.GetPosition($ThemeButton)
    $insideThemeButton = $themePoint.X -ge 0 -and $themePoint.Y -ge 0 -and $themePoint.X -le $ThemeButton.ActualWidth -and $themePoint.Y -le $ThemeButton.ActualHeight
    if (-not $insideFlyout -and -not $insideThemeButton) { Hide-ThemeFlyout }
})
$Window.Add_PreviewKeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.Key -eq [Windows.Input.Key]::Escape -and $ThemeFlyout.Visibility -eq 'Visible') {
        Hide-ThemeFlyout
        $eventArgs.Handled = $true
    }
})

$script:LogSearchTimer = New-Object Windows.Threading.DispatcherTimer
$script:LogSearchTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$script:LogSearchTimer.Add_Tick({
    $script:LogSearchTimer.Stop()
    Refresh-LogFilter
})
$LogLevelFilter.Add_SelectionChanged({ Refresh-LogFilter })
$LogSearchBox.Add_TextChanged({ $script:LogSearchTimer.Stop(); $script:LogSearchTimer.Start() })
$ClearLogButton.Add_Click({
    $script:LogEntries.Clear()
    Update-LogSummary
    Add-Log '日志已清空。' '信息' 'UI'
})
$CopyLogButton.Add_Click({
    try {
        $text = (@($script:LogEntries) | ForEach-Object { '[{0}] [{1}] [{2}] {3}' -f $_.Timestamp, $_.Level, $_.Source, $_.Message }) -join "`r`n"
        if ($text) { [Windows.Clipboard]::SetText($text); Add-Log '全部日志已复制到剪贴板。' '成功' 'UI' }
    } catch { Add-Log ('复制日志失败：' + $_.Exception.Message) '错误' 'UI' }
})

$LogToggle.Add_Click({
    if ($LogBox.Visibility -eq 'Visible') {
        $LogBox.Visibility = 'Collapsed'
        $LogToolbar.Visibility = 'Collapsed'
        $LogDivider.Visibility = 'Collapsed'
        $LogFooter.Visibility = 'Collapsed'
        $LogPanel.ClipToBounds = $true
        $LogPanel.Height = 46
        $LogToggle.Content = '展开日志'
    } else {
        $LogPanel.Height = [double]::NaN
        $LogToolbar.Visibility = 'Visible'
        $LogDivider.Visibility = 'Visible'
        $LogBox.Visibility = 'Visible'
        $LogFooter.Visibility = 'Visible'
        $LogPanel.MinHeight = 230
        $LogToggle.Content = '收起日志'
    }
})

$Window.Add_ContentRendered({
    foreach ($button in @($ThemeButton,$ThemeSystemButton,$ThemeDarkButton,$ThemeLightButton,$ThemePinkButton,$NativeButton,$ApplyButton,$Set1440Button,$Set1920Button,$DeviceButton,$RestoreButton,$LogToggle,$CopyLogButton,$ClearLogButton)) {
        $script:GlassController.Register($button)
    }
    Add-Log '界面已就绪，正在读取显示器状态。' '信息' 'UI'
    Start-StatusRefresh
})
$Window.Add_Deactivated({
    Hide-ThemeFlyout
    if ($script:GlassController) { $script:GlassController.Hide() }
})
$Window.Add_Closed({
    if ($script:GlassController) { $script:GlassController.Dispose() }
    $script:PollTimer.Stop()
    $script:LogSearchTimer.Stop()
    if ($script:StatusPowerShell) { try { $script:StatusPowerShell.Stop() } catch {}; $script:StatusPowerShell.Dispose() }
    if ($script:AsyncPowerShell) { try { $script:AsyncPowerShell.Stop() } catch {}; $script:AsyncPowerShell.Dispose() }
})

if ($TestMode) {
    $script:TestFailed = $false
    $script:TestCloseTimer = New-Object Windows.Threading.DispatcherTimer
    $script:TestCloseTimer.Interval = [TimeSpan]::FromSeconds(10)
    $script:TestCloseTimer.Add_Tick({
        $script:TestCloseTimer.Stop()
        try {
            foreach ($mode in @('Dark','Light','Pink','System','Dark')) {
                Apply-Theme $mode -Persist
                if (-not [IO.File]::Exists($SettingsPath)) { throw '主题设置未写入测试文件。' }
            }
            $ProgressText.Text = '  ·  隔离测试通过：主题切换与重复持久化正常。'
        } catch {
            Write-CrashReport '隔离测试失败' $_.Exception
            $ProgressText.Text = '  ·  隔离测试失败：' + $_.Exception.Message
            $script:TestFailed = $true
        }
        $Window.Close()
    })
    $Window.Add_ContentRendered({ $script:TestCloseTimer.Start() })
}

try {
    [void]$Window.ShowDialog()
} catch {
    Write-CrashReport 'WPF 主窗口发生未处理异常' $_.Exception
    [System.Windows.MessageBox]::Show(('界面发生异常：' + $_.Exception.Message + "`n`n诊断日志：" + $CrashLogPath), '显示模式控制台', 'OK', 'Error') | Out-Null
    exit 1
}
if ($TestMode -and $script:TestFailed) { exit 1 }
