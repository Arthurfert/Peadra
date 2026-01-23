import flet as ft
from flet.controls.layout_control import LayoutControl
from flet.controls.control import Control
from typing import Optional, List, Any
from flet_core.types import OptionalNumber
from flet_core.border import Border
from flet.controls.base_control import control
from dataclasses import field

# Import non-control data classes from flet_core
from flet_core.charts.chart_grid_lines import ChartGridLines
from flet_core.text_style import TextStyle

# Wrapper classes for Controls

@control("label")
class ChartAxisLabel(Control):
    value: float = 0.0
    label: Optional[Control] = None

    def _get_children(self):
        return [self.label] if self.label else []

@control("axis")
class ChartAxis(Control):
    title: Optional[Control] = None
    title_size: OptionalNumber = field(default=None, metadata={"alias": "titleSize"})
    show_labels: bool = field(default=True, metadata={"alias": "showLabels"})
    labels: Optional[List[ChartAxisLabel]] = None
    labels_interval: OptionalNumber = field(default=1.0, metadata={"alias": "labelsInterval"})
    labels_size: OptionalNumber = field(default=None, metadata={"alias": "labelsSize"})

    def _get_children(self):
        children = []
        if self.labels:
            children.extend(self.labels)
        if self.title:
            children.append(self.title)
        return children

@control("p")
class LineChartDataPoint(Control):
    x: float = 0.0
    y: float = 0.0

@control("data")
class LineChartData(Control):
    data_points: Optional[List[LineChartDataPoint]] = field(default=None)
    stroke_width: float = field(default=2.0, metadata={"alias": "strokeWidth"})
    color: Optional[str] = None
    curved: bool = False
    stroke_cap_round: bool = field(default=False, metadata={"alias": "strokeCapRound"})

    def _get_children(self):
        return self.data_points or []

@control("linechart")
class LineChart(LayoutControl):
    data_series: Optional[List[LineChartData]] = field(default=None)
    
    border: Optional[Border] = None
    horizontal_grid_lines: Optional[ChartGridLines] = field(default=None, metadata={"alias": "horizontalGridLines"})
    vertical_grid_lines: Optional[ChartGridLines] = field(default=None, metadata={"alias": "verticalGridLines"})
    
    left_axis: Optional[ChartAxis] = field(default=None, metadata={"alias": "leftAxis"})
    bottom_axis: Optional[ChartAxis] = field(default=None, metadata={"alias": "bottomAxis"})
    
    min_x: OptionalNumber = field(default=None, metadata={"alias": "minX"})
    max_x: OptionalNumber = field(default=None, metadata={"alias": "maxX"})
    min_y: OptionalNumber = field(default=None, metadata={"alias": "minY"})
    max_y: OptionalNumber = field(default=None, metadata={"alias": "maxY"})
    
    tooltip_bgcolor: Optional[str] = field(default=None, metadata={"alias": "tooltipBgcolor"})

    def _get_children(self):
        children = []
        if self.data_series:
            children.extend(self.data_series)
        if self.left_axis:
            children.append(self.left_axis)
        if self.bottom_axis:
            children.append(self.bottom_axis)
        return children

@control("rod")
class BarChartRod(Control):
    from_y: float = field(default=0.0, metadata={"alias": "fromY"})
    to_y: float = field(default=0.0, metadata={"alias": "toY"})
    width: OptionalNumber = None
    color: Optional[str] = None
    border_radius: Any = field(default=None, metadata={"alias": "borderRadius"})

@control("group")
class BarChartGroup(Control):
    x: int = 0
    bar_rods: Optional[List[BarChartRod]] = field(default=None, metadata={"alias": "barRods"})
    bars_space: OptionalNumber = field(default=None, metadata={"alias": "barsSpace"})

    def _get_children(self):
        return self.bar_rods or []

@control("barchart")
class BarChart(LayoutControl):
    bar_groups: Optional[List[BarChartGroup]] = field(default=None, metadata={"alias": "barGroups"})
    
    border: Optional[Border] = None
    left_axis: Optional[ChartAxis] = field(default=None, metadata={"alias": "leftAxis"})
    bottom_axis: Optional[ChartAxis] = field(default=None, metadata={"alias": "bottomAxis"})
    horizontal_grid_lines: Optional[ChartGridLines] = field(default=None, metadata={"alias": "horizontalGridLines"})
    
    min_y: OptionalNumber = field(default=None, metadata={"alias": "minY"})
    max_y: OptionalNumber = field(default=None, metadata={"alias": "maxY"})
    
    tooltip_bgcolor: Optional[str] = field(default=None, metadata={"alias": "tooltipBgcolor"})

    def _get_children(self):
        children = []
        if self.bar_groups:
            children.extend(self.bar_groups)
        if self.left_axis:
            children.append(self.left_axis)
        if self.bottom_axis:
            children.append(self.bottom_axis)
        return children

@control("section")
class PieChartSection(Control):
    value: float = 0.0
    title: str = ""
    title_style: Any = field(default=None, metadata={"alias": "titleStyle"})
    color: Optional[str] = None
    radius: OptionalNumber = None

@control("piechart")
class PieChart(LayoutControl):
    sections: Optional[List[PieChartSection]] = None
    sections_space: OptionalNumber = field(default=None, metadata={"alias": "sectionsSpace"})
    center_space_radius: OptionalNumber = field(default=None, metadata={"alias": "centerSpaceRadius"})
    on_chart_event: Optional[Any] = field(default=None, metadata={"alias": "onChartEvent"})

    def _get_children(self):
        return self.sections or []

